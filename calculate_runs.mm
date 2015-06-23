//
//  calculate_runs.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM


#include <stack>

#include "context.h"

#define kBBLMCommandRunKind             @"org.mazaitis.bblm.command"
#define	kBBLMParameterRunKind			@"org.mazaitis.bblm.parameter"
#define	kBBLMOptionRunKind				@"org.mazaitis.bblm.option"

static int skipRunChars(BBLMTextIterator* iter, SInt32* curr_pos_after, int n)
{
    for(int i=0; i < n; i++)
    {
        (*iter)++;
        (*curr_pos_after)++;
        
        if (!iter->InBounds())
        {
            return(1);
        }
    }
    return(0);
}

static bool testSingleCharCommand(UniChar curr_char)
{
    switch (curr_char)
    {
        case ' ':
        case ',':
        case ':':
        case ';':
        case '%':
        case '#':
        case '$':
        case '&':
            return true;
    }
    return false;
}

static SInt32 addRun(SInt32 &run_start_pos, SInt32 curr_pos_after, const BBLMCallbackBlock &bblm_callbacks, NSString *curr_run_string)
{
    bool result;
    
    if (curr_pos_after > run_start_pos) {
        result = bblmAddRun(&bblm_callbacks, LANGUAGE_CODE, curr_run_string, run_start_pos, curr_pos_after - run_start_pos);
        if (!result)
        {
            return false;
        }
    }
    return true;
}

void calculateRuns(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks)
{
    // We are concerned with five kinds of run:
    //
    // * kBBLMCommandRunKind      (ConTeXt commands \... )
    // * kBBLMParameterRunKind    (ConTeXt command parameters [...] )
    // * kBBLMOptionRunKind       (ConTeXt optional text {...} )
    // * kBBLMCommentRunKind      (used for comments; can be spell checked)
    // * kBBLMCodeRunKind         (used for document text; can be spell checked)
    //
    // ...in eleven states:
    //
    // * k_backslash            - We have a backslash, but we don't know waht to do with it yet.
    // * k_command              - Command name
    // * k_command_single       - Single character, non-alpha commands (supported by a static list)
    // * k_predicate            - Capture any command arguments and optional text
    // * k_parameter            - Command parameters
    // * k_parameter_last       - Capture last character of command parameters
    // * k_option               - Opening curly bracket
    // * k_option_text          - Delimited text
    // * k_option_last          - Closing curly bracket
    // * k_comment              - Comment to the end of the line
    // * k_text                 - Everything else

    
    BBLMTextIterator iter(params);      // Iterator as supplied by calling code
    UniChar curr_char;                  // Current character
    SInt32 curr_pos_after = 0;          // Track our position in the file
    SInt32 run_start_pos = 0;           // Track the beginning ot the previous run
    
    SInt32 backslash_pos = 0;           // Backslash position
    bool no_skip = false;               // Flag to track if we want to reprocess the current character in a different state
    
    enum RunKinds
    {
        k_backslash,
        k_command,
        k_command_single,
        k_predicate,
        k_parameter,
        k_parameter_last,
        k_option,
        k_option_text,
        k_option_last,
        k_comment,
        k_text
    };

    std::stack<RunKinds> pending_runs;
    
    run_start_pos  = params.fCalcRunParams.fStartOffset;
    curr_pos_after  = run_start_pos;
    iter += run_start_pos;
    
    // Let's assume we're starting with text
    pending_runs.push(k_text);
    NSString *curr_run_string = kBBLMCodeRunKind;
    
    while (iter.InBounds())
    {
        curr_char = *iter;
        
        no_skip = false;
        
        switch (pending_runs.top())
        {
            case k_backslash:
            {
                if (isalnum(curr_char))
                {
                    pending_runs.pop();
                    pending_runs.push(k_command);
                    if (addRun(run_start_pos, backslash_pos, bblm_callbacks, curr_run_string)) {run_start_pos = backslash_pos;} else {return;}
                }
                else if (testSingleCharCommand(curr_char))
                {
                    pending_runs.pop();
                    pending_runs.push(k_command_single);
                    if (addRun(run_start_pos, backslash_pos, bblm_callbacks, curr_run_string)) {run_start_pos = backslash_pos;} else {return;}
                }
                else
                {
                    pending_runs.pop();
                }
                    
                break;
            }
            case k_command:
            {
                curr_run_string = kBBLMCommandRunKind;

                if (curr_char == '%')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_comment);
                }
                else if (isalnum(curr_char))
                {
                    break;
                }
                else
                {
                    pending_runs.pop();
                    pending_runs.push(k_predicate);
                    no_skip=true;
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                }
                break;
            }
            case k_command_single:
            {
                curr_run_string = kBBLMCommandRunKind;
                if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                pending_runs.pop();
                
                break;
            }
            case k_predicate:
            {
                if (curr_char == '[')
                {
                    pending_runs.push(k_parameter);
                }
                else if (curr_char == '{')
                {
                    pending_runs.push(k_option);
                }
                else if (isspace(curr_char))
                {
                    break;
                }
                else
                {
                    pending_runs.pop();
                    no_skip = true;
                }
                break;
            }
            case k_parameter:
            {
                curr_run_string = kBBLMParameterRunKind;
                if (curr_char == '\\')
                {
                    backslash_pos = curr_pos_after;
                    pending_runs.push(k_backslash);
                }
                else if (curr_char == '{')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_option);
                }
                else if (curr_char == ']')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.pop();
                    pending_runs.push(k_parameter_last);
                }

                break;
            }
            case k_parameter_last:
            {
                curr_run_string = kBBLMParameterRunKind;
                pending_runs.pop();
                if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                no_skip = true;
                
                break;
            }
            case k_option:
            {
                curr_run_string = kBBLMOptionRunKind;
                if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                pending_runs.pop();
                pending_runs.push(k_option_text);
                no_skip = true;
                
                break;
            }
            case k_option_text:
            {
                curr_run_string = kBBLMCodeRunKind;
                if (curr_char == '\\')
                {
                    backslash_pos = curr_pos_after;
                    pending_runs.push(k_backslash);
                }
                else if (curr_char == '{')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_option);
                }
                else if (curr_char == '}')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.pop();
                    pending_runs.push(k_option_last);
                }
                
                break;
            }
            case k_option_last:
            {
                curr_run_string = kBBLMOptionRunKind;
                pending_runs.pop();
                if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                no_skip = true;
                
                break;
            }
            case k_comment:
            {
                curr_run_string = kBBLMCommentRunKind;
                // No need to change runKind if we're in a comment block
                if (iter.stricmp("\r%") == 0)
                {
                    // We want to skip twice in this case
                    skipRunChars(&iter, &curr_pos_after, 1);
                }
                // end of line with no next comment, so revert to previous run kind
                else if (curr_char == '\r')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.pop();
                }
                
                break;
            }
            case k_text:
            {
                curr_run_string = kBBLMCodeRunKind;
                if (curr_char == '%')
                {
                    pending_runs.push(k_comment);
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                }
                if (curr_char == '{')
                {
                    pending_runs.push(k_option);
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                }
                else if (curr_char == '\\')
                {
                    backslash_pos = curr_pos_after;
                    pending_runs.push(k_backslash);
                }
                
                break;
            }
        } // End Switch
        if (no_skip) {
            continue;
        }
        skipRunChars(&iter, &curr_pos_after, 1);
    }
    // Commit final run
    addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string);
    
    // Clean up 
    while (!pending_runs.empty())
    {
        pending_runs.pop();
    }
    
    return;
}
