/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CodeCoverage.cpp
 *  Derived from:
 *
 *  CodeCoverage.cpp
 *  LLVM
 */

#include "CoverageExporterJson.h"
#include "CoverageSummaryInfo.h"
#include "llvm/ProfileData/Coverage/CoverageMapping.h"
#include "llvm/ProfileData/Coverage/CoverageMappingReader.h"
#include "llvm/ProfileData/InstrProfReader.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/Path.h"

#include <iostream>

using namespace llvm;
using namespace coverage;

namespace {

thread_local static std::vector<std::unique_ptr<CoverageMappingReader>> CoverageReaders;
/// The implementation of the coverage tool.
class CodeCoverageTool {
public:
std::string getCoverageJson(std::string profdata, std::vector<std::string> covFilenames);

private:
/// Print the error message to the error output stream.
void error(const Twine &Message, StringRef Whence = "");

/// Print the warning message to the error output stream.
void warning(const Twine &Message, StringRef Whence = "");

/// Convert \p Path into an absolute path and append it to the list
/// of collected paths.
void addCollectedPath(const std::string &Path);

/// If \p Path is a regular file, collect the path. If it's a
/// directory, recursively collect all of the paths within the directory.
void collectPaths(const std::string &Path);

/// Retrieve a file status with a cache.
Optional<sys::fs::file_status> getFileStatus(StringRef FilePath);

/// Load the coverage mapping data. Return nullptr if an error occurred.
std::unique_ptr<CoverageMapping> load();

std::vector<StringRef> ObjectFilenames;

/// The path to the indexed profile.
std::string PGOFilename;

/// A list of input source files.
std::vector<std::string> SourceFiles;

/// File status cache used when finding the same file.
StringMap<Optional<sys::fs::file_status> > FileStatusCache;

/// The architecture the coverage mapping data targets.
std::vector<StringRef> CoverageArches;

 /// Added for DDSDKSwiftTesting efficency
 std::unique_ptr<CoverageMapping> loadCached();
};
}

static std::string getErrorString(const Twine &Message, StringRef Whence,
                                  bool Warning) {
    std::string Str = (Warning ? "warning" : "error");
    Str += ": ";
    if (!Whence.empty())
        Str += Whence.str() + ": ";
    Str += Message.str() + "\n";
    return Str;
}

void CodeCoverageTool::addCollectedPath(const std::string &Path) {
    SmallString<128> EffectivePath(Path);
    if (std::error_code EC = sys::fs::make_absolute(EffectivePath)) {
        error(EC.message(), Path);
        return;
    }
    sys::path::remove_dots(EffectivePath, /*remove_dot_dot=*/ true);
    SourceFiles.emplace_back(EffectivePath.str());
}

void CodeCoverageTool::collectPaths(const std::string &Path) {
    llvm::sys::fs::file_status Status;
    llvm::sys::fs::status(Path, Status);
    if (!llvm::sys::fs::exists(Status)) {
        warning("Source file doesn't exist, proceeded by ignoring it.", Path);
        return;
    }

    if (llvm::sys::fs::is_regular_file(Status)) {
        addCollectedPath(Path);
        return;
    }

    if (llvm::sys::fs::is_directory(Status)) {
        std::error_code EC;
        for (llvm::sys::fs::recursive_directory_iterator F(Path, EC), E;
             F != E; F.increment(EC)) {

            auto Status = F->status();
            if (!Status) {
                warning(Status.getError().message(), F->path());
                continue;
            }

            if (Status->type() == llvm::sys::fs::file_type::regular_file)
                addCollectedPath(F->path());
        }
    }
}

Optional<sys::fs::file_status>
CodeCoverageTool::getFileStatus(StringRef FilePath) {
    auto It = FileStatusCache.try_emplace(FilePath);
    auto &CachedStatus = It.first->getValue();
    if (!It.second)
        return CachedStatus;

    sys::fs::file_status Status;
    if (!sys::fs::status(FilePath, Status))
        CachedStatus = Status;
    return CachedStatus;
}

std::unique_ptr<CoverageMapping> CodeCoverageTool::load() {
    auto CoverageOrErr =
    CoverageMapping::load(ObjectFilenames, PGOFilename, CoverageArches,"");
    if (Error E = CoverageOrErr.takeError()) {

        error("Failed to load coverage: " + toString(std::move(E)),
              join(ObjectFilenames.begin(), ObjectFilenames.end(), ", "));
        return nullptr;
    }
    auto Coverage = std::move(CoverageOrErr.get());
    unsigned Mismatched = Coverage->getMismatchedCount();
    if (Mismatched) {
        warning(Twine(Mismatched) + " functions have mismatched data");
    }

    return Coverage;
}

// If E is a no_data_found error, returns success. Otherwise returns E.
static Error handleMaybeNoDataFoundError(Error E) {
    return handleErrors(
                        std::move(E), [](const CoverageMapError &CME) {
                            if (CME.get() == coveragemap_error::no_data_found)
                                return static_cast<Error>(Error::success());
                            return make_error<CoverageMapError>(CME.get());
                        });
}

//LLVM structs recreated
typedef struct BinaryCoverageReaderStruct {
    void *vTable;
    std::vector<std::string> Filenames;
    std::vector<BinaryCoverageReader::ProfileMappingRecord> MappingRecords;
    InstrProfSymtab ProfileNames;
    size_t CurrentRecord;
    std::vector<StringRef> FunctionsFilenames;
    std::vector<CounterExpression> Expressions;
    std::vector<CounterMappingRegion> MappingRegions;
    std::unique_ptr<MemoryBuffer> FuncRecords;
} BinaryCoverageReaderStruct;

std::unique_ptr<CoverageMapping> CodeCoverageTool::loadCached() {

    auto ProfileReaderOrErr = IndexedInstrProfReader::create(PGOFilename);
    if (Error E = ProfileReaderOrErr.takeError()){
        error("Failed to load coverage: " + toString(std::move(E)), PGOFilename);
        return nullptr;
    }
    auto ProfileReader = std::move(ProfileReaderOrErr.get());

    if( CoverageReaders.empty() ) {
        for (const auto &File : llvm::enumerate(ObjectFilenames)) {
            auto CovMappingBufOrErr = MemoryBuffer::getFileOrSTDIN(
                                                                   File.value(), /*IsText=*/false, /*RequiresNullTerminator=*/false);
            if (std::error_code EC = CovMappingBufOrErr.getError()) {
                return nullptr;
            }
            StringRef Arch = CoverageArches.empty() ? StringRef() : CoverageArches[File.index()];
            MemoryBufferRef CovMappingBufRef =
            CovMappingBufOrErr.get()->getMemBufferRef();
            SmallVector<std::unique_ptr<MemoryBuffer>, 4> Buffers;
            auto CoverageReadersOrErr = BinaryCoverageReader::create(CovMappingBufRef, Arch, Buffers, "");
            if (Error E = CoverageReadersOrErr.takeError()) {
                E = handleMaybeNoDataFoundError(std::move(E));
                if (E) {
                    return nullptr;
                }
                // E == success (originally a no_data_found error).
                continue;
            }

            for (auto &Reader : CoverageReadersOrErr.get()){
                CoverageReaders.push_back(std::move(Reader));
            }
        }
    } else {
        for (auto &Reader : CoverageReaders) {
            BinaryCoverageReaderStruct* fakeReader = (BinaryCoverageReaderStruct *)Reader.get();
            fakeReader->CurrentRecord = 0;
        }
    }
    
    auto Readers = ArrayRef(CoverageReaders);
    auto CoverageOrErr = CoverageMapping::load(Readers, *ProfileReader);
    if (Error E = CoverageOrErr.takeError()) {

        error("Failed to load coverage: " + toString(std::move(E)),
              join(ObjectFilenames.begin(), ObjectFilenames.end(), ", "));
        return nullptr;
    }
    auto Coverage = std::move(CoverageOrErr.get());
    unsigned Mismatched = Coverage->getMismatchedCount();
    if (Mismatched) {
        warning(Twine(Mismatched) + " functions have mismatched data");
    }
    return Coverage;
}

std::string CodeCoverageTool::getCoverageJson(std::string profdata, std::vector<std::string> covFilenames)  {

    PGOFilename = profdata;

    for (const std::string &Filename : covFilenames) {
        ObjectFilenames.emplace_back(Filename);
    }

    std::string outputString;
    raw_string_ostream string_stream(outputString);


    auto Coverage = loadCached();
    if (!Coverage) {
        printf("Could not load coverage information");
        return outputString;
    }

    std::unique_ptr<CoverageExporter> Exporter;

    Exporter = std::make_unique<CoverageExporterJson>(*Coverage.get(),  string_stream);

    if (SourceFiles.empty())
        Exporter->renderRoot();
    else
        Exporter->renderRoot(SourceFiles);

    return outputString;
}

void CodeCoverageTool::error(const Twine &Message, StringRef Whence) {
    std::cout << getErrorString(Message, Whence, false);
}

void CodeCoverageTool::warning(const Twine &Message, StringRef Whence) {
    std::cout << getErrorString(Message, Whence, true);
}

std::string getCoverage(std::string profdata, std::vector<std::string> covFilenames) {

    return CodeCoverageTool().getCoverageJson(profdata, covFilenames);

}
