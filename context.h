//
//  context.h
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM

#ifndef ConTeXt_context_h
#define ConTeXt_context_h

#include "BBLMInterface.h"
#include "BBLMTextIterator.h"

#define LANGUAGE_CODE 'cTeX'

OSErr scanForFunctions(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);

void calculateRuns(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks);

struct func_point_info
{
    UniChar ch = ' ';                   // The current character we're processing
    UInt32 pos = 0;                     // The current position in the file; we start at the first character
    UInt32 line_start = 0;              // Position of the start of the current line
    bool in_comment = false;            // Track if we are in a comment to suppress folds
};

struct runs_point_info
{
    UniChar ch;                         // Current character
    SInt32 pos = 0;                     // Track our position in the file
    SInt32 run_start = 0;               // Track the beginning ot the previous run
    UInt32 backslash = 0;               // Location of backslash to indicate command run start
    bool no_skip = false;               // Flag to track if we want to reprocess the current character in a different state
    bool visible_param_text = false;    // Track if current paramter value should be painted as plain text or parameter text
};

#endif
