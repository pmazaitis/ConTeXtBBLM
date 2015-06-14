//
//  calculate_runs.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis on 4/26/15.
//
//

#include <stack>
#include "context.h"

#define kBBLMCommandRunKind                 @"org.mazaitis.bblm.command"
#define	kBBLMParameterRunKind				@"org.mazaitis.bblm.parameter"
#define	kBBLMOptionRunKind					@"org.mazaitis.bblm.option"

static int skipRunChars(BBLMTextIterator* iter, SInt32* curr_pos, int n)
{
    for(int i=0; i < n; i++)
    {
        (*iter)++;
        (*curr_pos)++;
        
        if (!iter->InBounds())
        {
            return(1);
        }
    }
    return(0);
}

static SInt32 addRun(SInt32 &prev_pos, SInt32 curr_pos, const BBLMCallbackBlock &bblm_callbacks, NSString *curr_run_string)
{
    bool result;
    
    if (curr_pos > prev_pos) {
        result = bblmAddRun(&bblm_callbacks, LANGUAGE_CODE, curr_run_string, prev_pos, curr_pos - prev_pos);
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
    // * kBBLMOptionRunKind       (ConTeXt command options {...} )
    // * kBBLMCommentRunKind      (used for comments; can be spell checked)
    // * kBBLMCodeRunKind         (used for document text; can be spell checked)
    //
    // ...in ten states:
    //
    // * k_command
    // * k_predicate
    // * k_parameter
    // * k_parameter_last
    // * k_parameter_text
    // * k_parameter_text_last
    // * k_option
    // * k_option_last
    // * k_comment
    // * k_text

    
    BBLMTextIterator iter(params);      // Iterator as supplied by calling code
    UniChar curr_char, prev_char;       //
    SInt32 curr_pos;                    //
    SInt32 prev_pos;                    // The beginning of a ?
    bool no_skip = false;
    
    enum RunKinds
    {
        k_command,
        k_predicate,
        k_parameter,
        k_parameter_last,
        k_parameter_text,
        k_parameter_text_last,
        k_option,
        k_option_last,
        k_comment,
        k_text
    };

    std::stack<RunKinds> pending_runs;
    
    prev_pos  = params.fCalcRunParams.fStartOffset;
    curr_pos  = prev_pos;
    //curr_char = ' ';
    prev_char = ' ';
    iter += prev_pos;
    
    // Let's assume we're starting with text
    pending_runs.push(k_text);
    NSString *curr_run_string = kBBLMCodeRunKind;
    
    while (iter.InBounds())
    {
        curr_char = *iter;
        no_skip = false;
        
        switch (pending_runs.top())
        {
            case k_command:
                curr_run_string = kBBLMCommandRunKind;
                if (curr_char == '%' && prev_char != '\\')
                {
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                    pending_runs.pop();
                    pending_runs.push(k_comment);
                }
                else if (curr_char == '[' || curr_char == '{')
                {
                    pending_runs.pop();
                    pending_runs.push(k_predicate);
                    no_skip=true;
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                else if (curr_char == ' ' || curr_char == '~' || iter.stricmp("\r\r") == 0 || curr_char == ']' || curr_char == '}')
                {
                    pending_runs.pop();
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                    no_skip=true;
                }
                break;
            case k_predicate:
                if (curr_char == '[')
                {
                    pending_runs.push(k_parameter);
                }
                else if (curr_char == '{')
                {
                    pending_runs.push(k_option);
                }
                else
                {
                    pending_runs.pop();
                    no_skip=true;
                }
                break;
            case k_parameter:
                curr_run_string = kBBLMParameterRunKind;
                if (curr_char == ']')
                {
                    pending_runs.pop();
                    pending_runs.push(k_parameter_last);
                }
                else if (curr_char == '{')
                {
                    pending_runs.push(k_parameter_text);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                else if (iter.strcmp("\\\\") == 0) {
                    break;
                }
                else if (curr_char == '\\' && prev_char != '\\')
                {
                    pending_runs.push(k_command);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                break;
            case k_parameter_last:
                curr_run_string = kBBLMParameterRunKind;
                pending_runs.pop();
                no_skip=true;
                if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                break;
            case k_parameter_text:
                curr_run_string = kBBLMCodeRunKind;
                if (curr_char == '}')
                {
                    pending_runs.pop();
                    pending_runs.push(k_parameter_text_last);
                }
                else if (curr_char == '\\' && prev_char != '\\')
                {
                    pending_runs.push(k_command);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                break;
            case k_parameter_text_last:
                curr_run_string = kBBLMCodeRunKind;

                pending_runs.pop();
                no_skip=true;
                if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                
                break;
            case k_option:
                curr_run_string = kBBLMOptionRunKind;
                if (curr_char == '}')
                {
                    pending_runs.pop();
                    pending_runs.push(k_option_last);

                }
                else if (curr_char == '\\' && prev_char != '\\')
                {
                    pending_runs.push(k_command);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                break;
            case k_option_last:
                curr_run_string = kBBLMOptionRunKind;
                pending_runs.pop();
                if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                no_skip=true;
                break;
            case k_comment:
                curr_run_string = kBBLMCommentRunKind;
                // No need to change runKind if we're in a comment block
                if (iter.stricmp("\r%") == 0)
                {
                    skipRunChars(&iter, &curr_pos, 1);
                }
                // end of line with no next comment, so revert to previous run kind
                else if (curr_char == '\r')
                {
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                    pending_runs.pop();
                }
                break;
            case k_text:
                curr_run_string = kBBLMCodeRunKind;
                if (curr_char == '%' && prev_char != '\\')
                {
                    pending_runs.push(k_comment);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }
                else if (iter.strcmp("\\\\") == 0) {
                    break;
                }
                else if (iter.strcmp("\\%") == 0) {
                    break;
                }
                else if (curr_char == '\\' && prev_char != '\\')
                {
                    pending_runs.push(k_command);
                    if (addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string)) {prev_pos = curr_pos;} else {return;}
                }

                break;
        } // End Switch
        if (no_skip) {
            continue;
        }
        prev_char = curr_char;
        skipRunChars(&iter, &curr_pos, 1);
    }
    // Commit final run
    addRun(prev_pos, curr_pos, bblm_callbacks, curr_run_string);
    
    // Clean up 
    while (!pending_runs.empty())
    {
        pending_runs.pop();
    }
    
    return;
}
