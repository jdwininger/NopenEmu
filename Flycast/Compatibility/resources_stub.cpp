/*
    Resource loading implementation for OpenEmu.
    Loads fonts and assets from the CMakeRC embedded filesystem (flycast_resources_generated.cpp).
*/
#include "oslib/resources.h"
#include "archive/ZipArchive.h"
#include <cmrc/cmrc.hpp>
#include <cstring>

CMRC_DECLARE(flycast);

namespace resource
{

std::unique_ptr<u8[]> load(const std::string& path, size_t& size)
{
    try {
        cmrc::embedded_filesystem fs = cmrc::flycast::get_filesystem();
        std::string zipName = path + ".zip";
        if (fs.exists(zipName))
        {
            cmrc::file zipFile = fs.open(zipName);
            ZipArchive zip;
            if (zip.Open(zipFile.cbegin(), zipFile.size()))
            {
                std::unique_ptr<ArchiveFile> file;
                file.reset(zip.OpenFirstFile());
                if (file != nullptr)
                {
                    size = file->length();
                    std::unique_ptr<u8[]> buffer = std::make_unique<u8[]>(size);
                    size = file->Read(buffer.get(), size);
                    return buffer;
                }
            }
        }
        else
        {
            cmrc::file file = fs.open(path);
            size = file.size();
            std::unique_ptr<u8[]> buffer = std::make_unique<u8[]>(size);
            memcpy(buffer.get(), file.begin(), size);
            return buffer;
        }
    } catch (const std::system_error&) {
    }
    size = 0;
    return nullptr;
}

std::vector<std::string> listDirectory(const std::string& path)
{
    std::vector<std::string> v;
    try {
        cmrc::embedded_filesystem fs = cmrc::flycast::get_filesystem();
        for (auto entry : fs.iterate_directory(path))
            v.push_back(entry.filename());
    } catch (const std::system_error&) {
    }
    return v;
}

} // namespace resource
