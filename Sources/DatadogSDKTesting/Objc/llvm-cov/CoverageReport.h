/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageReport.h
 *  Derived from:
 *
 *  CoverageReport.h
 *  LLVM
 */

#ifndef LLVM_COV_COVERAGEREPORT_H
#define LLVM_COV_COVERAGEREPORT_H

#include "CoverageSummaryInfo.h"

namespace llvm {

/// Displays the code coverage report.
class CoverageReport {
  const coverage::CoverageMapping &Coverage;

  void render(const FileCoverageSummary &File, raw_ostream &OS) const;
  void render(const FunctionCoverageSummary &Function, const DemangleCache &DC,
              raw_ostream &OS) const;

public:
  CoverageReport(const coverage::CoverageMapping &Coverage)
      : Coverage(Coverage) {}

  void renderFunctionReports(ArrayRef<std::string> Files,
                             const DemangleCache &DC, raw_ostream &OS);

  /// Prepare file reports for the files specified in \p Files.
  static std::vector<FileCoverageSummary>
  prepareFileReports(const coverage::CoverageMapping &Coverage,
                     FileCoverageSummary &Totals, ArrayRef<std::string> Files);

  static void
  prepareSingleFileReport(const StringRef Filename,
                          const coverage::CoverageMapping *Coverage,
                          const unsigned LCP,
                          FileCoverageSummary *FileReport);

  /// Render file reports for every unique file in the coverage mapping.
  void renderFileReports(raw_ostream &OS) const;

  /// Render file reports for the files specified in \p Files.
  void renderFileReports(raw_ostream &OS, ArrayRef<std::string> Files) const;
};

} // end namespace llvm

#endif // LLVM_COV_COVERAGEREPORT_H
