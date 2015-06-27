//
//  scan_functions.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM


#include <string>
#include <stack>
#include <vector>

#include "context.h"
#include "syslog.h"

using namespace std;

struct func_point_info
{
    UniChar ch;                 // The current character we're processing
    UInt32 pos;                 // The current position in the file; we start at the first character
    UInt32 line_start;          // Position of the start of the current line
    bool in_comment;            // Track if we are in a comment to suppress folds
};

bool in_comment = false;

static bool skipChars(BBLMTextIterator* iter, func_point_info* p, int n)
{
    for(int i=0; i < n; i++)
    {
        if (!iter->InBounds())
        {
            // p->ch = **iter;
            return (1);
        }
//        else
//        {
//            return(1);
//        }
        
        // Do we have a new line?
        if (p->pos == 0)
        {
            p->line_start = 0;
        }
        else if (p->ch == '\r')
        {
            p->line_start = (p->pos) + 1;
        }
        
        // Are we in a comment block?
        if (p->ch == '%' && iter->GetPrevChar() != '\\')
        {
            iter->GetNextChar();
            p->in_comment = true;
        }
        else if (p->in_comment && p->ch == '\r')
        {
            p->in_comment = false;
        }
        
        //(*iter)++;
        p->ch = iter->GetNextChar();
        (p->pos)++;
        
    }
    return(0);
}


//static int skipChars(BBLMTextIterator* iter, UInt32* curr_pos, UInt32* line_start, int n)
//{
//    UniChar curr_char;
//    for(int i=0; i < n; i++)
//    {
//        if (iter->InBounds())
//        {
//            curr_char = **iter;
//        }
//        else
//        {
//            return(1);
//        }
//        
//        if (*curr_pos == 0)
//        {
//            *line_start = 0;
//        }
//        else if (curr_char == '\r')
//        {
//            *line_start = (*curr_pos) + 1;
//        }
//        // Are we in a comment block?
//        if (curr_char == '%' && iter->GetPrevChar() != '\\')
//        {
//            in_comment = true;
//            iter->GetNextChar();
//        }
//        else if (in_comment && curr_char == '\r')
//        {
//            in_comment = false;
//        }
//        
//        (*iter)++;
//        (*curr_pos)++;
//
//    }
//    return(0);
//}

OSErr scanForFunctions(BBLMParamBlock &params, const BBLMCallbackBlock &bblm_callbacks)
{
    //
    // # Description
    //
    // This scanner does two jobs: marking the file for folding, and selecting various
    // heads and callouts for display in the functions drop-down menu.
    //
    // ## Folding
    //
    // This scanner supports the following folds:
    //
    // * Folds from balanced pairs of /start and /stop commands
    // * A fold from the beginning of the document to /starttext, if applicable
    // * A fold from /stoptext to the end of the document, if applicable
    // * Folds for comment blocks of three or more lines
    //
    // ## Populating the Functions Menu
    //
    // When encountering a command, this scanner will test if the command
    // is a head command (/startchapter, /startsubject, etc.). The scanner
    // has a list of head commands for which it will generate an entry in the
    // functions list: if the found head type is on that list, an entry will
    // be added to the functions drop-down menu. The scanner keeps track of
    // nesting to try to match /start and /stop command correctly.
    //
    // The scanner will look for /setuphead commands, and add these commands to
    // the function drop-down as well.
    //
    // Indentation in the function drop-down reflects indentation in the document.
    //
    // The scanner will look for a set list of callouts, and add these callouts
    // to the function drop-down when found. Callouts are not indented.
    //
    // # Limitations
    //
    // * Can only handle files with size less than 2^32 bytes.
    // * Will automatically capture only the standard heading
    //   structure four levels deeper than _part_ for the functions list.
    // * Only supports mkiv style sectioning
    // * Will only find user-specified heads that are set up before use.
    
    BBLMTextIterator iter(params);  // Iterator as supplied by calling code
    OSErr  result = noErr;          // Return check

    func_point_info point;
    point.ch = ' ';                 // The current character we're processing
    point.pos = 0;                  // The current position in the file; we start at the first character
    point.line_start = 0;           // Position of the start of the current line
    point.in_comment = false;       // Track if we are in a comment to suppress folds
    
    // State stacks
    stack<UInt32> pending_funcs;    // Keep track of pending functions
    stack<string> pending_types;    // Keep track of pending function types
    stack<UInt32> pending_folds;    // Keep track of pending fold starts

    // Funcion Depth (we can't use the stack depth for this)
    int func_list_depth = 0;        // Keep track of visible funciton depth
    
    // Folds
    UInt32 fold_start = 0;          //
    UInt32 fold_length = 0;         //
    UInt32 comm_block_pos = 0;      // Start of possible comment block
    int consec_comment_lines = 0;   // How many consecutive lines of comments to we have?
    

    
    vector<string> valid_titles = { "part",
                                    "chapter",
                                    "section",
                                    "subsection",
                                    "subsubsection",
                                    "title",
                                    "subject",
                                    "subsubject",
                                    "subsubsubject"};
    
    iter += point.pos;
    
    while(iter.InBounds()) // While there are characters left...
    {
        //curr_ch = *iter;

        // Test for markers
        UInt32 callout_kind = 0;
        
        if (iter.strcmp("FIXME: ") == 0) {
            callout_kind = kBBLMFixMeCallout;
        }

        if (iter.strcmp("TODO: ") == 0) {
            callout_kind = kBBLMToDoCallout;
        }
        
        if (iter.strcmp("REVIEW: ") == 0) {
            callout_kind = kBBLMReviewCallout;
        }
        
        if (iter.strcmp("???: ") == 0) {
            callout_kind = kBBLMQuestionCallout;
        }

        if (iter.strcmp("!!!: ") == 0) {
            callout_kind = kBBLMWarningCallout;
        }
        
        if (iter.strcmp("NOTE: ") == 0) {
            callout_kind = kBBLMNoteCallout;
        }
        
        if (callout_kind != 0)
        {
            UInt32 func_start = point.pos;
            UInt32 func_stop = 0;
            UInt32 func_name_start = 0;
            UInt32 func_name_stop = 0;
            BBLMProcInfo info;
            
            OSErr err;
            
            vector<UniChar> curr_marker;
            
            func_name_start = point.pos;
            
            while (*iter != '\r') {
                // Collect Characters until we get to the end of the line
                //curr_ch = *iter;
                curr_marker.push_back(point.ch);
                skipChars(&iter, &point, 1);
            }
            
            func_stop = point.pos;
            func_name_stop = point.pos;
            
            // ident is the first Unichar of curr_marker
            UniChar *ident = &curr_marker[0];
            UInt32 offset = 0;
            UInt32 func_name_length = func_name_stop - func_name_start;
            
            // Set up the token
            err = bblmAddTokenToBuffer(&bblm_callbacks, params.fFcnParams.fTokenBuffer, ident, func_name_length, &offset);
            if (err)
            {
                return err;
            }
            
            // Set up the info stanza
            info.fFunctionStart = func_start;
            info.fFunctionEnd = func_stop;
            info.fSelStart = func_start;
            info.fSelEnd = func_stop;
            info.fFirstChar = func_start;
            info.fKind = callout_kind;
            info.fIndentLevel = 0;
            info.fFlags = 0;
            info.fNameStart = offset;
            info.fNameLength = func_name_length;
            
            UInt32 func_index = 0;
            err = bblmAddFunctionToList(&bblm_callbacks, params.fFcnParams.fFcnList,info, &func_index);
            if (err)
            {
                return err;
            }
        }
        
        // End testing for markers
        
        // Test for comment blocks
        
        if (point.line_start == point.pos && point.ch == '%')
        {
            if (consec_comment_lines == 0)
            {
                comm_block_pos = point.pos;
            }
            consec_comment_lines += 1;
        }
        else if (point.line_start == point.pos)
        {
            if (consec_comment_lines > 2)
            {
                comm_block_pos += 1;
                fold_length = point.pos - comm_block_pos - 1;
                if (fold_length > 0)
                {
                    result = bblmAddFoldRange(&bblm_callbacks, comm_block_pos, fold_length);
                    if (result)
                    {
                        return result;
                    }
                }
            }
            comm_block_pos = 0;
            consec_comment_lines = 0;
        }
        
        
        
        // End testing for comment blocks
        
        // Test for commands
        if (point.ch == '\\') // Found the start character of a ConTeXt command.
        {
            if (iter.stricmp("\\environment ") == 0) // Populate the includes pop-up with environment files
            {
                UInt32 func_start = point.pos;
                UInt32 func_stop = 0;
                UInt32 func_name_start = 0;
                UInt32 func_name_stop = 0;
                BBLMProcInfo info;
                OSErr err;
                
                vector<UniChar> curr_environment;
                
                skipChars(&iter, &point, 13);
                
                func_name_start = point.pos;
                
                while (*iter != '\r') {
                    // Collect Characters until we get to the end of the line
                    //curr_ch = *iter;
                    curr_environment.push_back(point.ch);
                    skipChars(&iter, &point, 1);
                }
                
                func_stop = point.pos;
                func_name_stop = point.pos;
                
                // ident is the first Unichar of curr_environment
                UniChar *ident = &curr_environment[0];
                
                UInt32 offset = 0;
                
                UInt32 func_name_length = func_name_stop - func_name_start;
                
                // Set up the token
                err = bblmAddTokenToBuffer(&bblm_callbacks, params.fFcnParams.fTokenBuffer, ident, func_name_length, &offset);
                if (err)
                {
                    return err;
                }
                
                // Set up the info stanza
                info.fFunctionStart = func_start;
                info.fFunctionEnd = func_stop;
                info.fSelStart = func_start;
                info.fSelEnd = func_stop;
                info.fFirstChar = func_start;
                info.fKind = kBBLMInclude;
                info.fIndentLevel = 0;
                info.fFlags = 0;
                info.fNameStart = offset;
                info.fNameLength = func_name_length;
                
                UInt32 func_index = 0;
                err = bblmAddFunctionToList(&bblm_callbacks, params.fFcnParams.fFcnList,info, &func_index);
                if (err)
                {
                    return err;
                }
            }
            if (iter.stricmp("\\definehead[") == 0) // We have a new head definition
            {
                string new_head_definition = "";
                skipChars(&iter, &point, 12);
                while (*iter != ']' && *iter != '\r')
                {
                    // Collect Characters until we get to the first square bracket
                    //curr_ch = *iter;
                    new_head_definition += point.ch;
                    skipChars(&iter, &point, 1);
                }
                valid_titles.push_back(new_head_definition); // Add our new definition to the list of valid heads
            }
            if (iter.strcmp("\\bTABLE") == 0 && !in_comment)
            {

                vector<UniChar> curr_function_type;

                while (iter.InBounds() && isalnum(*iter))
                {
                    // Collect Characters until we get to the end of the command
                    //curr_ch = *iter;
                    curr_function_type.push_back(point.ch);
                    skipChars(&iter, &point, 1);
                }
                //string func_type(curr_function_type.begin(), curr_function_type.end());
                //pending_types.push(func_type);
                pending_folds.push(point.pos);
            }
            if (iter.strcmp("\\eTABLE") == 0 && !in_comment)
            {
                OSErr err;
                if ( !pending_folds.empty())
                {
                    fold_start = pending_folds.top();
                    pending_folds.pop();
                }
                
                fold_length = point.pos - fold_start;
                if (fold_length > 0)
                {
                    err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
                    if (err)
                    {
                        return err;
                    }
                }
            }
            if (iter.strcmp("\\bTR") == 0 && !in_comment)
            {
                vector<UniChar> curr_function_type;
                
                while (iter.InBounds() && *iter != '[' && *iter != '\r' && *iter != ' ')
                {
                    // Collect Characters until we get to the end of the command
                    //curr_ch = *iter;
                    curr_function_type.push_back(point.ch);
                    skipChars(&iter, &point, 1);
                }
                //string func_type(curr_function_type.begin(), curr_function_type.end());
                //pending_types.push("bTR");
                pending_folds.push(point.pos);
            }
            if (iter.strcmp("\\eTR") == 0 && !in_comment)
            {
                OSErr err;
                if ( !pending_folds.empty())
                {
                    fold_start = pending_folds.top();
                    pending_folds.pop();
                }
                fold_length = point.pos - fold_start;
                if (fold_length > 0)
                {
                    err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
                    if (err)
                    {
                        return err;
                    }
                }
            }
            if (iter.stricmp("\\start") == 0) // Check if we have a start command.
            {
                UInt32 func_start;
                UInt32 func_stop = 0;
                UInt32 func_name_start = 0;
                UInt32 func_name_stop = 0;
                BBLMProcInfo info;
                OSErr err;
                vector<UniChar> curr_function_type;
                vector<UniChar> curr_function_name;
                
                func_start = point.pos;
                skipChars(&iter, &point, 6);
                
                while (iter.InBounds() && isalnum(*iter))
                {
                    // Collect Characters until we get to the end of the command
                    //curr_ch = *iter;
                    curr_function_type.push_back(point.ch);
                    skipChars(&iter, &point, 1);
                }
                
                string func_type(curr_function_type.begin(), curr_function_type.end());
                pending_types.push(func_type);
                if (!in_comment) pending_folds.push(point.pos);
                
                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), func_type) != valid_titles.end());
                
                if (func_type == "text" && !in_comment)
                {
                    // Close off preamble fold, end is linestart - 1
                    fold_start = 0;
                    fold_length = point.line_start - 1;
                    if (fold_length > 0)
                    {
                        err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
                        if (err)
                        {
                            return err;
                        }
                    }
                    
                }
                
                if (is_known_type)
                {
                    UInt32 func_name_length;
                    // string curr_name = "";
                    bool option_block_found = false;
                    
                    while (iter.InBounds() && *iter != ']' && *iter != '\r')
                    {
                        skipChars(&iter, &point, 1);
                        if (*iter != '[')
                        {
                            option_block_found = true;
                            break;
                        }
                    }
                    
                    while(option_block_found && iter.InBounds() &&  *iter != ']') // Look for a title= key, and capture if found
                    {
                        if (iter.stricmp("title") == 0)
                        {
                            while(iter.InBounds() &&  *iter != '{' && *iter != ']')
                            {
                                skipChars(&iter, &point, 1);
                            }
                            skipChars(&iter, &point, 1);
                            func_name_start = point.pos;
                            while(iter.InBounds() && *iter != '}' && *iter != ']')
                            {
                                //curr_ch = *iter;
                                curr_function_name.push_back(point.ch);
                                skipChars(&iter, &point, 1);
                            }
                            func_name_stop = point.pos;
                            func_stop = point.pos;
                        }
                        skipChars(&iter, &point, 1);
                    }
                    
                    // We have a better value for the start of the fold, so use it instead
                    if (!in_comment)
                    {
                        pending_folds.pop();
                        if (option_block_found) {
                            pending_folds.push(point.pos + 1);
                        }
                        else
                        {
                            pending_folds.push(point.pos);
                        }
                    }
                    
                   
                    
                    // If we have an empty curr_function_name, set it (and the ranges) to something sensible
                    if (curr_function_name.empty())
                    {
                        string dummy_header_text = "NOHEADER";
                        copy(dummy_header_text.begin(), dummy_header_text.end(), back_inserter(curr_function_name));
                        func_name_start = func_name_start -7;
                        func_name_stop = func_name_stop + 1;
                    }
                    else
                    {
                        
                    }
                    
                    
                    // Prepare for the Token
                    UInt32 offset = 0;
                    func_name_length = func_name_stop - func_name_start;
                    UniChar *ident = &curr_function_name[0];
                    // Set up the token
                    err = bblmAddTokenToBuffer(&bblm_callbacks, params.fFcnParams.fTokenBuffer, ident, func_name_length, &offset);
                    if (err)
                    {
                        return err;
                    }
                    
                    // Set up the info stanza
                    info.fFunctionStart = point.line_start;
                    info.fFunctionEnd = func_stop;
                    info.fSelStart = func_name_start;
                    info.fSelEnd = func_name_stop;
                    info.fFirstChar = func_start;
                    info.fKind = kBBLMFunctionMark;
                    info.fIndentLevel = func_list_depth;
                    info.fFlags = 0;
                    info.fNameStart = offset;
                    info.fNameLength = func_name_length;
                    
                    UInt32 func_index = 0;
                    err = bblmAddFunctionToList(&bblm_callbacks, params.fFcnParams.fFcnList,info, &func_index);
                    if (err)
                    {
                        return err;
                    }
                    pending_funcs.push(func_index);
                    func_list_depth++;
                }
            }
            if (iter.stricmp("\\stop") == 0) // Check if we have a stop command.
            {
                BBLMProcInfo info;
                OSErr err;
                vector<UniChar> curr_function_type;
                UInt32 curr_func_idx;
                string curr_func_type;
                
                skipChars(&iter, &point, 5);
                if ( !pending_folds.empty() && !in_comment)
                {
                    fold_start = pending_folds.top();
                    pending_folds.pop();
                }

                while (iter.InBounds() && isalnum(*iter))
                {
                    // Collect Characters until we get to the end of the command
                    //curr_ch = *iter;
                    curr_function_type.push_back(point.ch);
                    skipChars(&iter, &point, 1);
                }
                
                string func_type(curr_function_type.begin(), curr_function_type.end());
                
                if (func_type == "text")
                {
                    // Begin postamble fold
                    pending_folds.push(point.pos);
                }
                
                fold_length = point.pos - fold_start - 5 - func_type.length();
                if (fold_length > 0 && !in_comment)
                {
                    err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
                    if (err)
                    {
                        return err;
                    }
                }
                
                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), func_type) != valid_titles.end());
                
                if (is_known_type  && !pending_funcs.empty() && !pending_types.empty())
                {
                    // TODO:
                    curr_func_idx = pending_funcs.top();
                    curr_func_type = pending_types.top();
                    pending_funcs.pop();
                    pending_types.pop();
                    func_list_depth--;
                    
                    err = bblmGetFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
                    if (err)
                    {
                        return err;
                    }
                    while (iter.InBounds() &&  *iter != '[' && *iter != '\r')
                    {
                        skipChars(&iter, &point, 1);
                    }
                    info.fFunctionEnd = point.pos;
                    //info.fSelEnd = curr_pos;
                    err = bblmUpdateFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
                    if (err)
                    {
                        return err;
                    }
                }
            }
            
        } // End of test for start of command
        skipChars(&iter, &point, 1);
        if (in_comment) {syslog(LOG_WARNING, "###### BBEdit in comment.");} else {syslog(LOG_WARNING, "### BBEdit not in comment.");}
    } // End of Main While Loop
    
    if (!pending_folds.empty())
    {
        OSErr err;
        fold_start = pending_folds.top();
        fold_length = point.pos - fold_start;
        if (fold_length > 0)
        {
            err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
            if (err)
            {
                return err;
            }
        }
    }
    
    // Clean up
    while (!pending_funcs.empty())
    {
        pending_funcs.pop();
    }
    while (!pending_types.empty())
    {
        pending_types.pop();
    }
    while (!pending_folds.empty())
    {
        pending_folds.pop();
    }
    
    return result;
}