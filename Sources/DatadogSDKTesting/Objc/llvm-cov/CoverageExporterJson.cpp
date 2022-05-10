/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageExporterJson.cpp
 *  Derived from:
 *
 *  CoverageExporterJson.cpp
 *  LLVM
 */

#include "CoverageExporterJson.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/ThreadPool.h"

/// The semantic version combined as a string.
#define LLVM_COVERAGE_EXPORT_JSON_STR "3.0.1"

/// Unique type identifier for JSON coverage export.
#define LLVM_COVERAGE_EXPORT_JSON_TYPE_STR "llvm.coverage.json.export"

using namespace llvm;

namespace {

// The JSON library accepts int64_t, but profiling counts are stored as uint64_t.
// Therefore we need to explicitly convert from unsigned to signed, since a naive
// cast is implementation-defined behavior when the unsigned value cannot be
// represented as a signed value. We choose to clamp the values to preserve the
// invariant that counts are always >= 0.
int64_t clamp_uint64_to_int64(uint64_t u) {
  return std::min(u, static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
}

json::Array renderSegment(const coverage::CoverageSegment &Segment) {
  return json::Array({Segment.Line, Segment.Col,
                      clamp_uint64_to_int64(Segment.Count), Segment.HasCount,
                      Segment.IsRegionEntry, Segment.IsGapRegion});
}


json::Array renderFileSegments(const coverage::CoverageData &FileCoverage) {
  json::Array SegmentArray;
  for (const auto &Segment : FileCoverage)
    SegmentArray.push_back(renderSegment(Segment));
  return SegmentArray;
}

json::Object renderFile(const coverage::CoverageMapping &Coverage,
                        const std::string &Filename) {
  json::Object File({{"filename", Filename}});
  auto FileCoverage = Coverage.getCoverageForFile(Filename);
  File["segments"] = renderFileSegments(FileCoverage);
  return File;
}

json::Array renderFiles(const coverage::CoverageMapping &Coverage,
                        ArrayRef<std::string> SourceFiles) {
  ThreadPoolStrategy S = heavyweight_hardware_concurrency(SourceFiles.size());
  S.Limit = true;

  ThreadPool Pool(S);
  json::Array FileArray;
  std::mutex FileArrayMutex;

  for (unsigned I = 0, E = SourceFiles.size(); I < E; ++I) {
    auto &SourceFile = SourceFiles[I];
    Pool.async([&] {
      auto File = renderFile(Coverage, SourceFile);
      {
        std::lock_guard<std::mutex> Lock(FileArrayMutex);
        FileArray.push_back(std::move(File));
      }
    });
  }
  Pool.wait();
  return FileArray;
}

} // end anonymous namespace

void CoverageExporterJson::renderRoot() {
  std::vector<std::string> SourceFiles;
  for (StringRef SF : Coverage.getUniqueSourceFiles()) {
      SourceFiles.emplace_back(SF);
  }
  renderRoot(SourceFiles);
}

void CoverageExporterJson::renderRoot(ArrayRef<std::string> SourceFiles) {
  auto Files = renderFiles(Coverage, SourceFiles);
  // Sort files in order of their names.
  llvm::sort(Files, [](const json::Value &A, const json::Value &B) {
    const json::Object *ObjA = A.getAsObject();
    const json::Object *ObjB = B.getAsObject();
    assert(ObjA != nullptr && "Value A was not an Object");
    assert(ObjB != nullptr && "Value B was not an Object");
    const StringRef FilenameA = ObjA->getString("filename").getValue();
    const StringRef FilenameB = ObjB->getString("filename").getValue();
    return FilenameA.compare(FilenameB) < 0;
  });
  auto Export = json::Object({{"files", std::move(Files)}});

  auto ExportArray = json::Array({std::move(Export)});

    OS << json::Object({{"version", LLVM_COVERAGE_EXPORT_JSON_STR},
        {"type", LLVM_COVERAGE_EXPORT_JSON_TYPE_STR},
        {"data", std::move(ExportArray)}});
}
