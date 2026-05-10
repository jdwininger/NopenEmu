/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

#include "snes9x.h"
#include "memmap.h"
#include "display.h"
#include "msu1.h"
#include "apu/resampler.h"
#include "apu/bapu/dsp/blargg_endian.h"
#include <fstream>
#include <sys/stat.h>
#include <dirent.h>
#include <algorithm>
#include <vector>

STREAM dataStream = NULL;
STREAM audioStream = NULL;
uint32 audioLoopPos;
size_t partial_frames;

// Sample buffer
static Resampler *msu_resampler = NULL;

static void MSUTrace(const char *fmt, ...)
{
	(void)fmt;
}

static bool EndsWithCaseInsensitive(const std::string &value, const std::string &suffix)
{
	if (value.size() < suffix.size())
		return false;

	auto offset = value.size() - suffix.size();
	for (size_t i = 0; i < suffix.size(); i++)
	{
		if (tolower((unsigned char)value[offset + i]) != tolower((unsigned char)suffix[i]))
			return false;
	}

	return true;
}

static STREAM OpenMSUFileBySuffixInROMDir(const std::vector<std::string> &suffixes)
{
	std::string dir = S9xGetDirectory(ROMFILENAME_DIR);
	if (dir.empty())
	{
		MSUTrace("[MSU1] ROM directory is empty, suffix scan skipped.\n");
		return NULL;
	}

	MSUTrace("[MSU1] Suffix scan in ROM dir: %s\n", dir.c_str());

	DIR *d = opendir(dir.c_str());
	if (!d)
	{
		MSUTrace("[MSU1] Failed to open ROM directory for suffix scan: %s\n", dir.c_str());
		return NULL;
	}

	std::vector<std::string> entries;
	for (dirent *entry = readdir(d); entry != NULL; entry = readdir(d))
	{
		std::string name = entry->d_name;
		if (name == "." || name == "..")
			continue;
		entries.push_back(name);
	}

	closedir(d);
	std::sort(entries.begin(), entries.end());

	for (const auto &name : entries)
	{
		for (const auto &suffix : suffixes)
		{
			if (!EndsWithCaseInsensitive(name, suffix))
				continue;

			std::string path = dir;
			if (!path.empty() && path.back() != '/' && path.back() != '\\')
				path += '/';
			path += name;

			STREAM file = OPEN_STREAM(path.c_str(), "rb");
			if (file)
			{
				MSUTrace("[MSU1] Using suffix-matched file %s\n", path.c_str());
				return file;
			}
		}
	}

	MSUTrace("[MSU1] No files matched suffix scan.\n");

	return NULL;
}

#ifdef UNZIP_SUPPORT
static int unzFindExtension(unzFile &file, const char *ext, bool restart = TRUE, bool print = TRUE, bool allowExact = FALSE)
{
    unz_file_info	info;
    int				port, l = strlen(ext), e = allowExact ? 0 : 1;

    if (restart)
        port = unzGoToFirstFile(file);
    else
        port = unzGoToNextFile(file);

    while (port == UNZ_OK)
    {
        int		len;
        char	name[132];

        unzGetCurrentFileInfo(file, &info, name, 128, NULL, 0, NULL, 0);
        len = strlen(name);

        if (len >= l + e && strcasecmp(name + len - l, ext) == 0 && unzOpenCurrentFile(file) == UNZ_OK)
        {
            if (print)
                printf("Using msu file %s", name);

            return (port);
        }

        port = unzGoToNextFile(file);
    }

    return (port);
}
#endif

STREAM S9xMSU1OpenFile(const char *msu_ext, bool skip_unpacked)
{
    auto filename = S9xGetFilename(msu_ext, ROMFILENAME_DIR);
	STREAM file = 0;

	MSUTrace("[MSU1] Trying %s (skip_unpacked=%d)\n", filename.c_str(), skip_unpacked ? 1 : 0);

	if (!skip_unpacked)
	{
		file = OPEN_STREAM(filename.c_str(), "rb");
		if (file)
			MSUTrace("[MSU1] Using unpacked file %s\n", filename.c_str());
		else
			MSUTrace("[MSU1] Missing unpacked file %s\n", filename.c_str());
	}

#ifdef UNZIP_SUPPORT
    // look for msu1 pack file in the rom or patch dir if msu data file not found in rom dir
    if (!file)
    {
        auto zip_filename = S9xGetFilename(".msu1", ROMFILENAME_DIR);
		unzFile	unzFile = unzOpen(zip_filename.c_str());

		if (!unzFile)
		{
			zip_filename = S9xGetFilename(".msu1", PATCH_DIR);
			unzFile = unzOpen(zip_filename.c_str());
		}

        if (unzFile)
        {
			MSUTrace("[MSU1] Searching packed .msu1 for suffix %s\n", msu_ext);
            int	port = unzFindExtension(unzFile, msu_ext, true, true, true);
            if (port == UNZ_OK)
            {
                file = new unzStream(unzFile);
				MSUTrace("[MSU1] Using packed entry suffix %s\n", msu_ext);
            }
            else
			{
				MSUTrace("[MSU1] No packed entry found for suffix %s\n", msu_ext);
                unzClose(unzFile);
			}
        }
		else
			MSUTrace("[MSU1] No .msu1 archive found in ROM/PATCH directory.\n");
    }
#endif

    return file;
}

static void AudioClose()
{
	if (audioStream)
	{
		CLOSE_STREAM(audioStream);
		audioStream = NULL;
	}
}

static bool AudioOpen()
{
	MSU1.MSU1_STATUS |= AudioError;

	AudioClose();

	char extension[32];
	snprintf(extension, sizeof(extension), "-%u.pcm", MSU1.MSU1_CURRENT_TRACK);
    audioStream = S9xMSU1OpenFile(extension);

	// Many packs use zero-padded track numbering.
	if (!audioStream)
	{
		snprintf(extension, sizeof(extension), "-%02u.pcm", MSU1.MSU1_CURRENT_TRACK);
		audioStream = S9xMSU1OpenFile(extension);
	}

	if (!audioStream)
	{
		snprintf(extension, sizeof(extension), "-%03u.pcm", MSU1.MSU1_CURRENT_TRACK);
		audioStream = S9xMSU1OpenFile(extension);
	}

	if (!audioStream)
	{
		std::vector<std::string> suffixes;
		snprintf(extension, sizeof(extension), "-%u.pcm", MSU1.MSU1_CURRENT_TRACK);
		suffixes.emplace_back(extension);
		snprintf(extension, sizeof(extension), "-%02u.pcm", MSU1.MSU1_CURRENT_TRACK);
		suffixes.emplace_back(extension);
		snprintf(extension, sizeof(extension), "-%03u.pcm", MSU1.MSU1_CURRENT_TRACK);
		suffixes.emplace_back(extension);
		audioStream = OpenMSUFileBySuffixInROMDir(suffixes);
	}

	if (audioStream)
	{
		if (GETC_STREAM(audioStream) != 'M')
		{
			MSUTrace("[MSU1] PCM header mismatch at byte 0 for track %u\n", MSU1.MSU1_CURRENT_TRACK);
			return false;
		}
		if (GETC_STREAM(audioStream) != 'S')
		{
			MSUTrace("[MSU1] PCM header mismatch at byte 1 for track %u\n", MSU1.MSU1_CURRENT_TRACK);
			return false;
		}
		if (GETC_STREAM(audioStream) != 'U')
		{
			MSUTrace("[MSU1] PCM header mismatch at byte 2 for track %u\n", MSU1.MSU1_CURRENT_TRACK);
			return false;
		}
		if (GETC_STREAM(audioStream) != '1')
		{
			MSUTrace("[MSU1] PCM header mismatch at byte 3 for track %u\n", MSU1.MSU1_CURRENT_TRACK);
			return false;
		}

        READ_STREAM((char *)&audioLoopPos, 4, audioStream);
		audioLoopPos = GET_LE32(&audioLoopPos);
		audioLoopPos <<= 2;
		audioLoopPos += 8;

        MSU1.MSU1_AUDIO_POS = 8;

		MSU1.MSU1_STATUS &= ~AudioError;
		MSUTrace("[MSU1] Audio track %u opened successfully.\n", MSU1.MSU1_CURRENT_TRACK);
		return true;
	}

	MSUTrace("[MSU1] Failed to open PCM for track %u\n", MSU1.MSU1_CURRENT_TRACK);

	return false;
}

static void DataClose()
{
	if (dataStream)
	{
		CLOSE_STREAM(dataStream);
		dataStream = NULL;
	}
}

static bool DataOpen()
{
	DataClose();

    dataStream = S9xMSU1OpenFile(".msu");

	if(!dataStream)
		dataStream = S9xMSU1OpenFile("msu1.rom");

	if(!dataStream)
		dataStream = OpenMSUFileBySuffixInROMDir({".msu"});

	MSUTrace("[MSU1] DataOpen %s\n", dataStream ? "succeeded" : "failed");

	return dataStream != NULL;
}

void S9xResetMSU(void)
{
	MSU1.MSU1_STATUS		= 0;
	MSU1.MSU1_DATA_SEEK		= 0;
	MSU1.MSU1_DATA_POS		= 0;
	MSU1.MSU1_TRACK_SEEK	= 0;
	MSU1.MSU1_CURRENT_TRACK = 0;
	MSU1.MSU1_RESUME_TRACK	= 0;
	MSU1.MSU1_VOLUME		= 0;
	MSU1.MSU1_CONTROL		= 0;
	MSU1.MSU1_AUDIO_POS		= 0;
	MSU1.MSU1_RESUME_POS	= 0;

	if (msu_resampler)
		msu_resampler->clear();

	partial_frames = 0;

	DataClose();

	AudioClose();

	Settings.MSU1 = S9xMSU1ROMExists();
}

void S9xMSU1Init(void)
{
	DataOpen();
}

void S9xMSU1DeInit(void)
{
	DataClose();
	AudioClose();
}

bool S9xMSU1ROMExists(void)
{
    STREAM s = S9xMSU1OpenFile(".msu");
	if (!s)
		s = S9xMSU1OpenFile("msu1.rom");
	if (!s)
		s = OpenMSUFileBySuffixInROMDir({".msu"});

	if (s)
	{
		CLOSE_STREAM(s);
		return true;
	}
#ifdef UNZIP_SUPPORT

	if (splitpath(Memory.ROMFilename).ext_is(".msu1"))
		return true;

    // Accept non-matching basenames by looking for any .msu1 archive in ROM dir.
    STREAM archive = OpenMSUFileBySuffixInROMDir({".msu1"});
	if (archive)
	{
		CLOSE_STREAM(archive);
		return true;
	}

	unzFile unzFile = unzOpen(S9xGetFilename(".msu1", ROMFILENAME_DIR).c_str());

	if(!unzFile)
		unzFile = unzOpen(S9xGetFilename(".msu1", PATCH_DIR).c_str());

	if (unzFile)
	{
		unzClose(unzFile);
		return true;
	}
#endif
    return false;
}

void S9xMSU1Generate(size_t sample_count)
{
	partial_frames += 4410 * (sample_count / 2);

	while (partial_frames >= 3204)
	{
		if (MSU1.MSU1_STATUS & AudioPlaying && audioStream)
		{
			int32 sample;
			int16* left = (int16*)&sample;
			int16* right = left + 1;

			int bytes_read = READ_STREAM((char *)&sample, 4, audioStream);
			if (bytes_read == 4)
			{
				*left = ((int32)(int16)GET_LE16(left) * MSU1.MSU1_VOLUME / 255);
				*right = ((int32)(int16)GET_LE16(right) * MSU1.MSU1_VOLUME / 255);

				msu_resampler->push_sample(*left, *right);
				MSU1.MSU1_AUDIO_POS += 4;
				partial_frames -= 3204;
			}
			else
			if (bytes_read >= 0)
			{
				if (MSU1.MSU1_STATUS & AudioRepeating)
				{
					if (audioLoopPos < MSU1.MSU1_AUDIO_POS)
					{
						MSU1.MSU1_AUDIO_POS = audioLoopPos;
					}
					else // if the loop point is invalid, revert to start
					{
						MSU1.MSU1_AUDIO_POS = 8;
					}
					REVERT_STREAM(audioStream, MSU1.MSU1_AUDIO_POS, 0);
				}
				else
				{
					MSU1.MSU1_STATUS &= ~(AudioPlaying | AudioRepeating);
					REVERT_STREAM(audioStream, 8, 0);
				}
			}
			else
			{
				MSU1.MSU1_STATUS &= ~(AudioPlaying | AudioRepeating);
			}
		}
		else
		{
			MSU1.MSU1_STATUS &= ~(AudioPlaying | AudioRepeating);
			partial_frames -= 3204;
			msu_resampler->push_sample(0, 0);
		}
	}
}


uint8 S9xMSU1ReadPort(uint8 port)
{
	switch (port)
	{
	case 0:
		return MSU1.MSU1_STATUS | MSU1_REVISION;
	case 1:
    {
        if (MSU1.MSU1_STATUS & DataBusy)
            return 0;
        if (!dataStream)
            return 0;
        int data = GETC_STREAM(dataStream);
        if (data >= 0)
        {
            MSU1.MSU1_DATA_POS++;
            return data;
        }
        return 0;
    }
	case 2:
		return 'S';
	case 3:
		return '-';
	case 4:
		return 'M';
	case 5:
		return 'S';
	case 6:
		return 'U';
	case 7:
		return '1';
	}

	return 0;
}


void S9xMSU1WritePort(uint8 port, uint8 byte)
{
	switch (port)
	{
	case 0:
		MSU1.MSU1_DATA_SEEK &= 0xFFFFFF00;
		MSU1.MSU1_DATA_SEEK |= byte << 0;
		break;
	case 1:
		MSU1.MSU1_DATA_SEEK &= 0xFFFF00FF;
		MSU1.MSU1_DATA_SEEK |= byte << 8;
		break;
	case 2:
		MSU1.MSU1_DATA_SEEK &= 0xFF00FFFF;
		MSU1.MSU1_DATA_SEEK |= byte << 16;
		break;
	case 3:
		MSU1.MSU1_DATA_SEEK &= 0x00FFFFFF;
		MSU1.MSU1_DATA_SEEK |= byte << 24;
		MSU1.MSU1_DATA_POS = MSU1.MSU1_DATA_SEEK;
        if (dataStream)
        {
            REVERT_STREAM(dataStream, MSU1.MSU1_DATA_POS, 0);
        }
		break;
	case 4:
		MSU1.MSU1_TRACK_SEEK &= 0xFF00;
		MSU1.MSU1_TRACK_SEEK |= byte;
		break;
	case 5:
		MSU1.MSU1_TRACK_SEEK &= 0x00FF;
		MSU1.MSU1_TRACK_SEEK |= (byte << 8);
		MSU1.MSU1_CURRENT_TRACK = MSU1.MSU1_TRACK_SEEK;

		MSU1.MSU1_STATUS &= ~AudioPlaying;
		MSU1.MSU1_STATUS &= ~AudioRepeating;

		if (AudioOpen())
		{
			if (MSU1.MSU1_CURRENT_TRACK == MSU1.MSU1_RESUME_TRACK)
			{
				MSU1.MSU1_AUDIO_POS = MSU1.MSU1_RESUME_POS;
				MSU1.MSU1_RESUME_POS = 0;
				MSU1.MSU1_RESUME_TRACK = ~0;
			}
			else
			{
				MSU1.MSU1_AUDIO_POS = 8;
			}

            REVERT_STREAM(audioStream, MSU1.MSU1_AUDIO_POS, 0);
		}
		break;
	case 6:
		MSU1.MSU1_VOLUME = byte;
		break;
	case 7:
		if (MSU1.MSU1_STATUS & (AudioBusy | AudioError))
			break;

		MSU1.MSU1_STATUS = (MSU1.MSU1_STATUS & ~0x30) | ((byte & 0x03) << 4);

		if ((byte & (Play | Resume)) == Resume)
		{
			MSU1.MSU1_RESUME_TRACK = MSU1.MSU1_CURRENT_TRACK;
			MSU1.MSU1_RESUME_POS = MSU1.MSU1_AUDIO_POS;
		}
		break;
	}
}

size_t S9xMSU1Samples(void)
{
	return msu_resampler->space_filled();
}

void S9xMSU1SetOutput(Resampler *resampler)
{
	msu_resampler = resampler;
}

void S9xMSU1PostLoadState(void)
{
	if (DataOpen())
	{
        REVERT_STREAM(dataStream, MSU1.MSU1_DATA_POS, 0);
	}

	if (MSU1.MSU1_STATUS & AudioPlaying)
	{
		uint32 savedPosition = MSU1.MSU1_AUDIO_POS;

		if (AudioOpen())
		{
            REVERT_STREAM(audioStream, 4, 0);
            READ_STREAM((char *)&audioLoopPos, 4, audioStream);
			audioLoopPos = GET_LE32(&audioLoopPos);
			audioLoopPos <<= 2;
			audioLoopPos += 8;

			MSU1.MSU1_AUDIO_POS = savedPosition;
            REVERT_STREAM(audioStream, MSU1.MSU1_AUDIO_POS, 0);
		}
		else
		{
			MSU1.MSU1_STATUS &= ~(AudioPlaying | AudioRepeating);
			MSU1.MSU1_STATUS |= AudioError;
		}
	}

	if (msu_resampler)
		msu_resampler->clear();

	partial_frames = 0;
}
