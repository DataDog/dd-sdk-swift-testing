/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageExporter.h
 *  Derived from:
 *
 *  CoverageExporter.h
 *  LLVM
 */

#ifndef LLVM_COV_COVERAGEEXPORTER_H
#define LLVM_COV_COVERAGEEXPORTER_H

#include "llvm/ProfileData/Coverage/CoverageMapping.h"

namespace llvm {

/// Exports the code coverage information.
class CoverageExporter {
protected:
  /// The full CoverageMapping object to export.
  const coverage::CoverageMapping &Coverage;

  /// Output stream to print to.
  raw_ostream &OS;
  //  std::string &OS;

  CoverageExporter(const coverage::CoverageMapping &CoverageMapping,  raw_ostream &OS)
      : Coverage(CoverageMapping), OS(OS) {}

public:
  virtual ~CoverageExporter(){};

  /// Render the CoverageMapping object.
  virtual void renderRoot() = 0;

  /// Render the CoverageMapping object for specified source files.
  virtual void renderRoot(ArrayRef<std::string> SourceFiles) = 0;
};

} // end namespace llvm

#endif // LLVM_COV_COVERAGEEXPORTER_H
