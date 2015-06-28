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
    UniChar prev;               // Previous character, for escape checking
    UInt32 pos;                 // The current position in the file; we start at the first character
    UInt32 line_start;          // Position of the start of the current line
    bool in_comment;            // Track if we are in a comment to suppress folds
};

struct fold_info
{
    UInt32 start = 0;           // Start position of the fold
    string name = "";           // Command name of the fold
};


static bool skipChars(BBLMTextIterator* iter, func_point_info* p, int n)
{
    for(int i=0; i < n; i++)
    {
        p->prev = p->ch;
        (*iter)++;
        (p->pos)++;
        
        if (iter->InBounds())
        {
            p->ch = **iter;
        }
        else
        {
            return(true);
        }
        
        // Do we have a new line?
        if (p->ch == '\r')
        {
            p->line_start = (p->pos) + 1;
        }
        
        // Are we in a comment?
        if (p->ch == '%' && p->prev != '\\')
        {
            syslog(LOG_WARNING,"### Switch into Comment at %d", (int) p->pos);
            p->in_comment = true;
        }
        if (p->in_comment && p->ch == '\r')
        {
            syslog(LOG_WARNING,"### Switch into Text at %d", (int) p->pos);
            p->in_comment = false;
        }
        
    }
    return(false);
}

static bool skipWhiteSpace(BBLMTextIterator* iter, func_point_info* p)
{
    while (isspace(p->ch))
    {
        p->prev = p->ch;
        (*iter)++;
        (p->pos)++;
        
        if (iter->InBounds())
        {
            p->ch = **iter;
        }
        else
        {
            return(true);
        }
        
        // Do we have a new line?
        if (p->ch == '\r')
        {
            p->line_start = (p->pos) + 1;
        }
    }
    return(false);
}

static bool skipToWhiteSpace(BBLMTextIterator* iter, func_point_info* p)
{
    while (!isspace(p->ch))
    {
        p->prev = p->ch;
        (*iter)++;
        (p->pos)++;
        
        if (iter->InBounds())
        {
            p->ch = **iter;
        }
        else
        {
            return(true);
        }
        
        // Do we have a new line?
        if (p->ch == '\r')
        {
            p->line_start = (p->pos) + 1;
        }
    }
    return(false);
}

//static bool getCommandName(BBLMTextIterator* iter, func_point_info* p, vector<UniChar>* c_id)
//{
//    // Collect Characters until we get to the end of the command
//    while ((**iter) == '\\' || isalnum(**iter))
//    {
//        c_id->push_back(p->ch);
//        if (skipChars(iter, p, 1)) return true;
//    }
//    return(false);
//}

static bool getCommandType(BBLMTextIterator* iter, func_point_info* p, vector<UniChar>* c_id, int n)
{
    // Skip requested characters to get to the relevant bit of the command
    for(int i=0; i < n; i++)
    {
        if (skipChars(iter, p, 1)) return true;
    }
    // Collect Characters until we get to the end of the command
    while (isalnum(**iter))
    {
        c_id->push_back(p->ch);
        if (skipChars(iter, p, 1)) return true;
    }
    return(false);
}


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
    point.prev = ' ';               // The previous character
    point.pos = 0;                  // The current position in the file; we start at the first character
    point.line_start = 0;           // Position of the start of the current line
    point.in_comment = false;       // Track if we are in a comment to suppress folds
    
    // State stacks
    stack<UInt32> pending_funcs;    // Keep track of pending functions
    //stack<string> pending_types;    // Keep track of pending function types
    stack<UInt32> pending_folds;    // Keep track of pending fold starts
    stack<fold_info> pend_folds; // Keep track of pending folds

    // Function Depth (we can't use the stack depth for this)
    //int func_list_depth = 0;        // Keep track of visible funciton depth
    
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
    
    iter += point.pos; // TODO: do we ever want to get this value from the params block?
    
    point.ch = *iter;
    point.line_start = 0;
    if (point.ch == '%')
    {
        point.in_comment = true;
    }
    
    while(true) // We test for our out of bounds conditions when skipping characters
    {
        // Test for markers
        {
        UInt32 callout_kind = 0;
        
        if (iter.strcmp("FIXME: ") == 0) {
            callout_kind = kBBLMFixMeCallout;
        }

        else if (iter.strcmp("TODO: ") == 0) {
            callout_kind = kBBLMToDoCallout;
        }
        
        else if (iter.strcmp("REVIEW: ") == 0) {
            callout_kind = kBBLMReviewCallout;
        }
        
        else if (iter.strcmp("???: ") == 0) {
            callout_kind = kBBLMQuestionCallout;
        }

        else if (iter.strcmp("!!!: ") == 0) {
            callout_kind = kBBLMWarningCallout;
        }
        
        else if (iter.strcmp("NOTE: ") == 0) {
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
                if (skipChars(&iter, &point, 1)) break;
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
        
        }
        // End testing for markers
        
        // Test for comment blocks
        {
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
        
        }
        // End testing for comment blocks
        
        // Test for commands
        if (point.ch == '\\') // Found the start character of a ConTeXt command.
        {
            if (iter.stricmp("\\environment") == 0) // Populate the includes pop-up with environment files
            {
                UInt32 func_start = point.pos;
                UInt32 func_stop = 0;
                UInt32 func_name_start = 0;
                UInt32 func_name_stop = 0;
                BBLMProcInfo info;
                OSErr err;
                
                vector<UniChar> curr_environment;
                
                if (skipToWhiteSpace(&iter, &point)) break;
                if (skipWhiteSpace(&iter, &point)) break;
                
                func_name_start = point.pos;
                
                while (!isspace(*iter)) {
                    // Collect characters in the referenced file until we get to whitespace
                    curr_environment.push_back(point.ch);
                    if (skipChars(&iter, &point, 1)) break;
                }
                
                func_stop = point.pos;
                func_name_stop = point.pos;
                
                // ident is the first Unichar of curr_environment
                UniChar *ident = &curr_environment[0];
                
                UInt32 offset = 0;
                
                UInt32 func_name_length = func_name_stop - func_name_start;
                
                //addFunction(
                
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
            if (iter.stricmp("\\definehead") == 0) // We have a new head definition
            {
                string new_head_definition = "";

                while (*iter != '[')
                {
                    if (skipChars(&iter, &point, 1)) break;
                }
                // Eat the [
                if (skipChars(&iter, &point, 1)) break;
                while (*iter != ']' && *iter != '\r')
                {
                    // Collect Characters until we get to the ending square bracket
                    new_head_definition += point.ch;
                    if (skipChars(&iter, &point, 1)) break;
                }
                valid_titles.push_back(new_head_definition); // Add our new definition to the list of valid heads
            }
            if (!point.in_comment && (iter.strcmp("\\bTABLE") == 0 || iter.strcmp("\\bTR") == 0))
            {
                vector<UniChar> curr_id;    // Text of current command
                fold_info curr_fold;        // Fold from the top of the fold stack
                int TYPE_SKIP = 2;          // Number of characters to skip to get to command type
                
                curr_fold.start = point.line_start;
                // Pull the command type into a vector
                if (getCommandType(&iter, &point, &curr_id, TYPE_SKIP)) break;
                // Set the values for the fold, and add it to the stack
                curr_fold.name.assign(curr_id.begin(), curr_id.end());
                curr_fold.start += curr_fold.name.length() + TYPE_SKIP;
                pend_folds.push(curr_fold);
            }
            if (!point.in_comment && (iter.strcmp("\\eTABLE") == 0 || iter.strcmp("\\eTR") == 0))
            {
                OSErr err;                  // Return check
                vector<UniChar> curr_id;    // Text of current command
                fold_info curr_fold;        // Fold from the top of the fold stack
                int TYPE_SKIP = 2;          // Number of characters to skip to get to command type
                string tt;                  // temp string of current command
               
                if (getCommandType(&iter, &point, &curr_id, TYPE_SKIP)) break;
                tt.assign(curr_id.begin(), curr_id.end());
                
                if ( !pend_folds.empty())
                {
                    curr_fold = pend_folds.top();
                    
                    if (curr_fold.name.compare(tt) == 0 )
                    {
                        pend_folds.pop();
                        fold_length = point.pos - curr_fold.start - tt.length() - TYPE_SKIP;
                        if (fold_length > 0)
                        {
                            err = bblmAddFoldRange(&bblm_callbacks, curr_fold.start, fold_length);
                            if (err)
                            {
                                return err;
                            }
                        }
                    }
                }
            }
//            if (iter.stricmp("\\start") == 0) // Check if we have a start command.
//            {
//                UInt32 func_start;
//                UInt32 func_stop = 0;
//                UInt32 func_name_start = 0;
//                UInt32 func_name_stop = 0;
//                BBLMProcInfo info;
//                OSErr err;
//                vector<UniChar> curr_function_type;
//                vector<UniChar> curr_function_name;
//                
//                func_start = point.pos;
//                if (skipChars(&iter, &point, 6)) break;
//                
//                while (iter.InBounds() && isalnum(*iter))
//                {
//                    // Collect Characters until we get to the end of the command
//                    //curr_ch = *iter;
//                    curr_function_type.push_back(point.ch);
//                    if (skipChars(&iter, &point, 1)) break;
//                }
//                
////                string func_type(curr_function_type.begin(), curr_function_type.end());
////                pending_types.push(func_type);
//                pending_folds.push(point.pos);
//                
//                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), func_type) != valid_titles.end());
//                
//                if (func_type == "text")
//                {
//                    // Close off preamble fold, end is linestart - 1
//                    fold_start = 0;
//                    fold_length = point.line_start - 1;
//                    if (fold_length > 0)
//                    {
//                        err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
//                        if (err)
//                        {
//                            return err;
//                        }
//                    }
//                    
//                }
//                
//                if (is_known_type)
//                {
//                    UInt32 func_name_length;
//                    // string curr_name = "";
//                    bool option_block_found = false;
//                    
//                    while (iter.InBounds() && *iter != ']' && *iter != '\r')
//                    {
//                        if (skipChars(&iter, &point, 1)) break;
//                        if (*iter != '[')
//                        {
//                            option_block_found = true;
//                            break;
//                        }
//                    }
//                    
//                    while(option_block_found && iter.InBounds() &&  *iter != ']') // Look for a title= key, and capture if found
//                    {
//                        if (iter.stricmp("title") == 0)
//                        {
//                            while(iter.InBounds() &&  *iter != '{' && *iter != ']')
//                            {
//                                if (skipChars(&iter, &point, 1)) break;
//                            }
//                            if (skipChars(&iter, &point, 1)) {return result;}
//                            func_name_start = point.pos;
//                            while(iter.InBounds() && *iter != '}' && *iter != ']')
//                            {
//                                //curr_ch = *iter;
//                                curr_function_name.push_back(point.ch);
//                                if (skipChars(&iter, &point, 1)) break;
//                            }
//                            func_name_stop = point.pos;
//                            func_stop = point.pos;
//                        }
//                        if (skipChars(&iter, &point, 1)) break;
//                    }
//                    
//                    // We have a better value for the start of the fold, so use it instead
//
//                        pending_folds.pop();
//                        if (option_block_found) {
//                            pending_folds.push(point.pos + 1);
//                        }
//                        else
//                        {
//                            pending_folds.push(point.pos);
//                        }
//                    
//                    
//                   
//                    
//                    // If we have an empty curr_function_name, set it (and the ranges) to something sensible
//                    if (curr_function_name.empty())
//                    {
//                        string dummy_header_text = "NOHEADER";
//                        copy(dummy_header_text.begin(), dummy_header_text.end(), back_inserter(curr_function_name));
//                        func_name_start = func_name_start -7;
//                        func_name_stop = func_name_stop + 1;
//                    }
//                    else
//                    {
//                        
//                    }
//                    
//                    
//                    // Prepare for the Token
//                    UInt32 offset = 0;
//                    func_name_length = func_name_stop - func_name_start;
//                    UniChar *ident = &curr_function_name[0];
//                    // Set up the token
//                    err = bblmAddTokenToBuffer(&bblm_callbacks, params.fFcnParams.fTokenBuffer, ident, func_name_length, &offset);
//                    if (err)
//                    {
//                        return err;
//                    }
//                    
//                    // Set up the info stanza
//                    info.fFunctionStart = point.line_start;
//                    info.fFunctionEnd = func_stop;
//                    info.fSelStart = func_name_start;
//                    info.fSelEnd = func_name_stop;
//                    info.fFirstChar = func_start;
//                    info.fKind = kBBLMFunctionMark;
//                    info.fIndentLevel = func_list_depth;
//                    info.fFlags = 0;
//                    info.fNameStart = offset;
//                    info.fNameLength = func_name_length;
//                    
//                    UInt32 func_index = 0;
//                    err = bblmAddFunctionToList(&bblm_callbacks, params.fFcnParams.fFcnList,info, &func_index);
//                    if (err)
//                    {
//                        return err;
//                    }
//                    pending_funcs.push(func_index);
//                    func_list_depth++;
//                }
//            }
//            if (iter.stricmp("\\stop") == 0) // Check if we have a stop command.
//            {
//                BBLMProcInfo info;
//                OSErr err;
//                vector<UniChar> curr_function_type;
//                UInt32 curr_func_idx;
//                string curr_func_type;
//                
//                if (skipChars(&iter, &point, 5)) break;
//                if ( !pending_folds.empty())
//                {
//                    fold_start = pending_folds.top();
//                    pending_folds.pop();
//                }
//
//                while (iter.InBounds() && isalnum(*iter))
//                {
//                    // Collect Characters until we get to the end of the command
//                    //curr_ch = *iter;
//                    curr_function_type.push_back(point.ch);
//                    if (skipChars(&iter, &point, 1)) break;
//                }
//                
//                string func_type(curr_function_type.begin(), curr_function_type.end());
//                
//                if (func_type == "text")
//                {
//                    // Begin postamble fold
//                    pending_folds.push(point.pos);
//                }
//                
//                fold_length = point.pos - fold_start - 5 - func_type.length();
//                if (fold_length > 0)
//                {
//                    err = bblmAddFoldRange(&bblm_callbacks, fold_start, fold_length);
//                    if (err)
//                    {
//                        return err;
//                    }
//                }
//                
//                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), func_type) != valid_titles.end());
//                
//                if (is_known_type  && !pending_funcs.empty())
//                {
//                    // TODO:
//                    curr_func_idx = pending_funcs.top();
//                    pending_funcs.pop();
//                    func_list_depth--;
//                    
//                    err = bblmGetFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
//                    if (err)
//                    {
//                        return err;
//                    }
//                    while (iter.InBounds() &&  *iter != '[' && *iter != '\r')
//                    {
//                        if (skipChars(&iter, &point, 1)) break;
//                    }
//                    info.fFunctionEnd = point.pos;
//                    //info.fSelEnd = curr_pos;
//                    err = bblmUpdateFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
//                    if (err)
//                    {
//                        return err;
//                    }
//                }
//            }
            
        } // End of test for start of command
        if (skipChars(&iter, &point, 1)) break;
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
//    while (!pending_types.empty())
//    {
//        pending_types.pop();
//    }
    while (!pending_folds.empty())
    {
        pending_folds.pop();
    }
    
    return result;
}