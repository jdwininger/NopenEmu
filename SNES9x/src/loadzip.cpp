/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

#ifdef UNZIP_SUPPORT

#include <assert.h>
#include <ctype.h>
#ifdef SYSTEM_ZIP
#include <minizip/unzip.h>
#else
#include "unzip/unzip.h"
#endif
#include "snes9x.h"
#include "memmap.h"

static const char *S9xZipBasename(const char *path)
{
	const char *name = strrchr(path, '/');
#ifdef _WIN32
	const char *name2 = strrchr(path, '\\');
	if (!name || (name2 && name2 > name))
		name = name2;
#endif
	return name ? name + 1 : path;
}

static bool S9xZipHasExt(const char *name, const char *ext)
{
	int len = (int) strlen(name);
	int extlen = (int) strlen(ext);

	return len > extlen && strcasecmp(name + len - extlen, ext) == 0;
}

static bool S9xLooksLikeSNESRom(const char *name)
{
	return S9xZipHasExt(name, ".sfc") ||
		   S9xZipHasExt(name, ".smc") ||
		   S9xZipHasExt(name, ".swc") ||
		   S9xZipHasExt(name, ".fig") ||
		   S9xZipHasExt(name, ".rom") ||
		   S9xZipHasExt(name, ".bin");
}


bool8 LoadZip (const char *zipname, uint32 *TotalFileSize, uint8 *buffer)
{
	*TotalFileSize = 0;

	unzFile	file = unzOpen(zipname);
	if (file == NULL)
		return (FALSE);

	bool isMSU1 = false;
	int ziplen = strlen(zipname);
	if (ziplen > 5 && strcasecmp(zipname + ziplen - 5, ".msu1") == 0)
		isMSU1 = true;

	// find largest file in zip file (under MAX_ROM_SIZE) or a file with extension .1, or a file named program.rom
	char	filename[132];
	char	msu1rom[132];
	filename[0] = 0;
	msu1rom[0] = 0;
	uint32	msu1romsize = 0;
	uint32	filesize = 0;
	int		port = unzGoToFirstFile(file);

	unz_file_info	info;

	while (port == UNZ_OK)
	{
		char	name[132];
		unzGetCurrentFileInfo(file, &info, name, 128, NULL, 0, NULL, 0);
		const char *base = S9xZipBasename(name);

		int namelen = strlen(name);
		if (namelen == 0 || name[namelen - 1] == '/')
		{
			port = unzGoToNextFile(file);
			continue;
		}

		if (strncasecmp(name, "__MACOSX/", 9) == 0 || strncmp(base, "._", 2) == 0)
		{
			port = unzGoToNextFile(file);
			continue;
		}

		if (info.uncompressed_size > CMemory::MAX_ROM_SIZE + 512)
		{
			port = unzGoToNextFile(file);
			continue;
		}

		if (isMSU1 && S9xLooksLikeSNESRom(base))
		{
			if (info.uncompressed_size > msu1romsize || msu1rom[0] == 0)
			{
				strcpy(msu1rom, name);
				msu1romsize = info.uncompressed_size;
			}

			if (strcasecmp(base, "program.rom") == 0)
			{
				strcpy(filename, name);
				filesize = info.uncompressed_size;
				break;
			}
		}

		if (info.uncompressed_size > filesize)
		{
			strcpy(filename, name);
			filesize = info.uncompressed_size;
		}

		int	len = strlen(name);
		if (len > 2 && name[len - 2] == '.' && name[len - 1] == '1')
		{
			strcpy(filename, name);
			filesize = info.uncompressed_size;
			break;
		}

		if (strcasecmp(base, "program.rom") == 0)
		{
			strcpy(filename, name);
			filesize = info.uncompressed_size;
			break;
		}

		port = unzGoToNextFile(file);
	}

	if (isMSU1 && msu1rom[0] != 0 && strcasecmp(S9xZipBasename(filename), "program.rom") != 0)
	{
		strcpy(filename, msu1rom);
		filesize = msu1romsize;
	}

	if (!(port == UNZ_END_OF_LIST_OF_FILE || port == UNZ_OK) || filesize == 0 ||
		(isMSU1 && !S9xLooksLikeSNESRom(S9xZipBasename(filename))))
	{
		if (unzClose(file) != UNZ_OK)
			assert(FALSE);
		return (FALSE);
	}

	// find extension
	char	tmp[2] = { 0, 0 };
	char	*ext = strrchr(filename, '.');
	if (ext)
		ext++;
	else
		ext = tmp;

	uint8	*ptr = buffer;
	bool8	more = FALSE;

	unzLocateFile(file, filename, 0);
	unzGetCurrentFileInfo(file, &info, filename, 128, NULL, 0, NULL, 0);

	if (unzOpenCurrentFile(file) != UNZ_OK)
	{
		unzClose(file);
		return (FALSE);
	}

	do
	{
		assert(info.uncompressed_size <= CMemory::MAX_ROM_SIZE + 512);

		uint32 FileSize = info.uncompressed_size;
		int	l = unzReadCurrentFile(file, ptr, FileSize);

		if (unzCloseCurrentFile(file) == UNZ_CRCERROR)
		{
			unzClose(file);
			return (FALSE);
		}

		if (l <= 0 || l != (int) FileSize)
		{
			unzClose(file);
			return (FALSE);
		}

		FileSize = Memory.HeaderRemove(FileSize, ptr);
		ptr += FileSize;
		*TotalFileSize += FileSize;

		int	len;

		if (ptr - Memory.ROM < CMemory::MAX_ROM_SIZE + 512 && (isdigit(ext[0]) && ext[1] == 0 && ext[0] < '9'))
		{
			more = TRUE;
			ext[0]++;
		}
		else
		if (ptr - Memory.ROM < CMemory::MAX_ROM_SIZE + 512)
		{
			if (ext == tmp)
				len = strlen(filename);
			else
				len = ext - filename - 1;

			if ((len == 7 || len == 8) && strncasecmp(filename, "sf", 2) == 0 &&
				isdigit(filename[2]) && isdigit(filename[3]) && isdigit(filename[4]) &&
				isdigit(filename[5]) && isalpha(filename[len - 1]))
			{
				more = TRUE;
				filename[len - 1]++;
			}
		}
		else
			more = FALSE;

		if (more)
		{
			if (unzLocateFile(file, filename, 0) != UNZ_OK ||
				unzGetCurrentFileInfo(file, &info, filename, 128, NULL, 0, NULL, 0) != UNZ_OK ||
				unzOpenCurrentFile(file) != UNZ_OK)
				break;
		}
	} while (more);

	unzClose(file);

	return (TRUE);
}

#endif
