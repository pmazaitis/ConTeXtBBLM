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



static bool skipRunChars(BBLMTextIterator* iter, SInt32* curr_pos_after, int n)
{
    for(int i=0; i < n; i++)
    {
        (*iter)++;
        (*curr_pos_after)++;
        
        if (!iter->InBounds())
        {
            return(true);
        }
    }
    return(false);
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
        case '{':
        case '}':
            return true;
            break;
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
    // * kBBLMCommandRunKind    - ConTeXt commands \...
    // * kBBLMParameterRunKind  - ConTeXt command parameters [...]
    // * kBBLMOptionRunKind     - ConTeXt optional text {...}
    // * kBBLMCommentRunKind    - used for comments; can be spell checked
    // * kBBLMCodeRunKind       - used for document text; can be spell checked
    //
    // ...in fourteen states:
    //
    // * k_backslash            - We have a backslash, but we don't know what to do with it yet.
    // * k_command              - Command name
    // * k_command_single       - Single character, non-alpha commands (supported by a static list)
    // * k_predicate            - Capture any command arguments and optional text
    // * k_parameter            - Command parameters
    // * k_parameter_last       - Capture last character of command parameters
    // * k_paramtext            - Opening curly bracket in a parameter
    // * k_paramtext_text       - Delimited text: runkind determined by visibility
    // * k_paramtext_last       - Closing curly bracket in a parameter
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
    bool visible_param_text = false;    // Flag to track if we want to treat parameter value as visible text
    
    enum RunKinds
    {
        k_backslash,
        k_command,
        k_command_single,
        k_predicate,
        k_parameter,
        k_parameter_last,
        k_paramtext,
        k_paramtext_text,
        k_paramtext_last,
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
                if (curr_char == '\\')
                {
                    no_skip = true;
                }
                break;
            }
            case k_predicate:
            {
                if (curr_char == '%')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_comment);
                }
                else if (curr_char == '[')
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
                // For any of the following keys, we want the value to be syntax colored as plain text.
                if ((iter.stricmp("title") == 0) ||
                    (iter.stricmp("bookmark") == 0) ||
                    (iter.stricmp("author") == 0) ||
                    (iter.stricmp("keyword") == 0) ||
                    (iter.stricmp("subtitle") == 0))
                {
                    visible_param_text = true;
                }
                if (curr_char == '%')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_comment);
                }
                else if (curr_char == '\\')
                {
                    backslash_pos = curr_pos_after;
                    pending_runs.push(k_backslash);
                }
                else if (curr_char == '{')
                {
                    if (visible_param_text)
                    {
                        if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                        pending_runs.push(k_paramtext);
                        visible_param_text = false;
                    }
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
            case k_paramtext:
            {
                curr_run_string = kBBLMParameterRunKind;
                if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                pending_runs.pop();
                pending_runs.push(k_paramtext_text);
                no_skip = true;
                
                break;
            }
            case k_paramtext_text:
            {
                curr_run_string = kBBLMCodeRunKind;
                if (curr_char == '%')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_comment);
                }
                else if (curr_char == '\\')
                {
                    backslash_pos = curr_pos_after;
                    pending_runs.push(k_backslash);
                }
                else if (curr_char == '{')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_paramtext);
                }
                else if (curr_char == '}')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.pop();
                    pending_runs.push(k_paramtext_last);
                }
                
                break;
            }
            case k_paramtext_last:
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
                if (curr_char == '%')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.push(k_comment);
                }
                else if (curr_char == '\\')
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
                    if (skipRunChars(&iter, &curr_pos_after, 1)) return;
                }
                // end of line with no next comment, so revert to previous run kind
                else if (curr_char == '\r')
                {
                    if (addRun(run_start_pos, curr_pos_after, bblm_callbacks, curr_run_string)) {run_start_pos = curr_pos_after;} else {return;}
                    pending_runs.pop();
                    if (pending_runs.top() == k_predicate)
                    {
                        no_skip = true;
                    }
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
        if (skipRunChars(&iter, &curr_pos_after, 1)) return;
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
