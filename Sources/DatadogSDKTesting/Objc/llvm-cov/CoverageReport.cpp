/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageReport.cpp
 *  Derived from:
 *
 *  CoverageReport.cpp
 *  LLVM
 */

#include "CoverageReport.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/ThreadPool.h"

using namespace llvm;

namespace {
/// Get the number of redundant path components in each path in \p Paths.
unsigned getNumRedundantPathComponents(ArrayRef<std::string> Paths) {
  // To start, set the number of redundant path components to the maximum
  // possible value.
  SmallVector<StringRef, 8> FirstPathComponents{sys::path::begin(Paths[0]),
                                                sys::path::end(Paths[0])};
  unsigned NumRedundant = FirstPathComponents.size();

  for (unsigned I = 1, E = Paths.size(); NumRedundant > 0 && I < E; ++I) {
    StringRef Path = Paths[I];
    for (const auto &Component :
         enumerate(make_range(sys::path::begin(Path), sys::path::end(Path)))) {
      // Do not increase the number of redundant components: that would remove
      // useful parts of already-visited paths.
      if (Component.index() >= NumRedundant)
        break;

      // Lower the number of redundant components when there's a mismatch
      // between the first path, and the path under consideration.
      if (FirstPathComponents[Component.index()] != Component.value()) {
        NumRedundant = Component.index();
        break;
      }
    }
  }

  return NumRedundant;
}

/// Determine the length of the longest redundant prefix of the paths in
/// \p Paths.
unsigned getRedundantPrefixLen(ArrayRef<std::string> Paths) {
  // If there's at most one path, no path components are redundant.
  if (Paths.size() <= 1)
    return 0;

  unsigned PrefixLen = 0;
  unsigned NumRedundant = getNumRedundantPathComponents(Paths);
  auto Component = sys::path::begin(Paths[0]);
  for (unsigned I = 0; I < NumRedundant; ++I) {
    auto LastComponent = Component;
    ++Component;
    PrefixLen += Component - LastComponent;
  }
  return PrefixLen;
}

} // end anonymous namespace

namespace llvm {
void CoverageReport::prepareSingleFileReport(const StringRef Filename,
    const coverage::CoverageMapping *Coverage, const unsigned LCP,
    FileCoverageSummary *FileReport) {
  for (const auto &Group : Coverage->getInstantiationGroups(Filename)) {
    std::vector<FunctionCoverageSummary> InstantiationSummaries;
    for (const coverage::FunctionRecord *F : Group.getInstantiations()) {
      auto InstantiationSummary = FunctionCoverageSummary::get(*Coverage, *F);
      FileReport->addInstantiation(InstantiationSummary);
      InstantiationSummaries.push_back(InstantiationSummary);
    }
    if (InstantiationSummaries.empty())
      continue;

    auto GroupSummary =
        FunctionCoverageSummary::get(Group, InstantiationSummaries);

    FileReport->addFunction(GroupSummary);
  }
}

std::vector<FileCoverageSummary> CoverageReport::prepareFileReports(
    const coverage::CoverageMapping &Coverage, FileCoverageSummary &Totals,
    ArrayRef<std::string> Files) {
  unsigned LCP = getRedundantPrefixLen(Files);

  ThreadPoolStrategy S = heavyweight_hardware_concurrency(Files.size());
S.Limit = true;
  ThreadPool Pool(S);

  std::vector<FileCoverageSummary> FileReports;
  FileReports.reserve(Files.size());

  for (StringRef Filename : Files) {
    FileReports.emplace_back(Filename.drop_front(LCP));
    Pool.async(&CoverageReport::prepareSingleFileReport, Filename,
               &Coverage, LCP, &FileReports.back());
  }
  Pool.wait();

  for (const auto &FileReport : FileReports)
  Totals += FileReport;

  return FileReports;
}

} // end namespace llvm
