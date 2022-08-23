/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2020-2022 Datadog, Inc.
 *
 *
 *  CoverageSummaryInfo.h
 *  Derived from:
 *
 *  CoverageSummaryInfo.h
 *  LLVM
 */


#ifndef LLVM_COV_COVERAGESUMMARYINFO_H
#define LLVM_COV_COVERAGESUMMARYINFO_H

#include "llvm/ProfileData/Coverage/CoverageMapping.h"

namespace llvm {

/// Provides information about region coverage for a function/file.
class RegionCoverageInfo {
/// The number of regions that were executed at least once.
size_t Covered;

/// The total number of regions in a function/file.
size_t NumRegions;

public:
RegionCoverageInfo() : Covered(0), NumRegions(0) {
}

RegionCoverageInfo(size_t Covered, size_t NumRegions)
	: Covered(Covered), NumRegions(NumRegions) {
	assert(Covered <= NumRegions && "Covered regions over-counted");
}

RegionCoverageInfo &operator+=(const RegionCoverageInfo &RHS) {
	Covered += RHS.Covered;
	NumRegions += RHS.NumRegions;
	return *this;
}

void merge(const RegionCoverageInfo &RHS) {
	Covered = std::max(Covered, RHS.Covered);
	NumRegions = std::max(NumRegions, RHS.NumRegions);
}

size_t getCovered() const {
	return Covered;
}

size_t getNumRegions() const {
	return NumRegions;
}

bool isFullyCovered() const {
	return Covered == NumRegions;
}

double getPercentCovered() const {
	assert(Covered <= NumRegions && "Covered regions over-counted");
	if (NumRegions == 0)
		return 0.0;
	return double(Covered) / double(NumRegions) * 100.0;
}
};

/// Provides information about function coverage for a file.
class FunctionCoverageInfo {
/// The number of functions that were executed.
size_t Executed;

/// The total number of functions in this file.
size_t NumFunctions;

public:
FunctionCoverageInfo() : Executed(0), NumFunctions(0) {
}

FunctionCoverageInfo(size_t Executed, size_t NumFunctions)
	: Executed(Executed), NumFunctions(NumFunctions) {
}

FunctionCoverageInfo &operator+=(const FunctionCoverageInfo &RHS) {
	Executed += RHS.Executed;
	NumFunctions += RHS.NumFunctions;
	return *this;
}

void addFunction(bool Covered) {
	if (Covered)
		++Executed;
	++NumFunctions;
}

size_t getExecuted() const {
	return Executed;
}

size_t getNumFunctions() const {
	return NumFunctions;
}

bool isFullyCovered() const {
	return Executed == NumFunctions;
}

double getPercentCovered() const {
	assert(Executed <= NumFunctions && "Covered functions over-counted");
	if (NumFunctions == 0)
		return 0.0;
	return double(Executed) / double(NumFunctions) * 100.0;
}
};

/// A summary of function's code coverage.
struct FunctionCoverageSummary {
	std::string Name;
	uint64_t ExecutionCount;
	RegionCoverageInfo RegionCoverage;

	FunctionCoverageSummary(const std::string &Name)
		: Name(Name), ExecutionCount(0) {
	}

	FunctionCoverageSummary(const std::string &Name, uint64_t ExecutionCount,
	                        const RegionCoverageInfo &RegionCoverage)
		: Name(Name), ExecutionCount(ExecutionCount),
		RegionCoverage(RegionCoverage) {
	}

	/// Compute the code coverage summary for the given function coverage
	/// mapping record.
	static FunctionCoverageSummary get(const coverage::CoverageMapping &CM,
	                                   const coverage::FunctionRecord &Function);

	/// Compute the code coverage summary for an instantiation group \p Group,
	/// given a list of summaries for each instantiation in \p Summaries.
	static FunctionCoverageSummary
	get(const coverage::InstantiationGroup &Group,
	    ArrayRef<FunctionCoverageSummary> Summaries);
};

/// A summary of file's code coverage.
struct FileCoverageSummary {
	StringRef Name;
	RegionCoverageInfo RegionCoverage;
	FunctionCoverageInfo FunctionCoverage;
	FunctionCoverageInfo InstantiationCoverage;

	FileCoverageSummary(StringRef Name) : Name(Name) {
	}

	FileCoverageSummary &operator+=(const FileCoverageSummary &RHS) {
		RegionCoverage += RHS.RegionCoverage;
		FunctionCoverage += RHS.FunctionCoverage;
		InstantiationCoverage += RHS.InstantiationCoverage;
		return *this;
	}

	void addFunction(const FunctionCoverageSummary &Function) {
		RegionCoverage += Function.RegionCoverage;
		FunctionCoverage.addFunction(/*Covered=*/ Function.ExecutionCount > 0);
	}

	void addInstantiation(const FunctionCoverageSummary &Function) {
		InstantiationCoverage.addFunction(/*Covered=*/ Function.ExecutionCount > 0);
	}
};

/// A cache for demangled symbols.
struct DemangleCache {
	StringMap<std::string> DemangledNames;

	/// Demangle \p Sym if possible. Otherwise, just return \p Sym.
	StringRef demangle(StringRef Sym) const {
		const auto DemangledName = DemangledNames.find(Sym);
		if (DemangledName == DemangledNames.end())
			return Sym;
		return DemangledName->getValue();
	}
};

} // namespace llvm

#endif // LLVM_COV_COVERAGESUMMARYINFO_H
