//
//  scan_functions.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM


// TODO: puzzle out comment block folding behavior

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
    UInt32 prev_start;          // Position of the start of the previous line
    UInt32 line_number;         // Track the number of lines for initial fold
    bool in_comment;            // Track if we are in a comment to suppress folds
};

struct fold_info
{
    UInt32 start = 0;           // Start position of the fold
    string name = "";           // Command name of the fold
};

struct func_info
{
    UInt32 index = 0;           // Index of the function
    string name = "";           // Command name of the function
};

// skipChars - skip over a set number of chars, keeping track of state
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
        if (p->prev == '\r')
        {
            p->prev_start = p->line_start;
            p->line_start = (p->pos);
            p->line_number += 1;
        }
        
        // Are we in a comment?
        if (p->ch == '%' && p->prev != '\\')
        {
            p->in_comment = true;
        }
        if (p->in_comment && p->ch == '\r')
        {
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
        if (p->prev == '\r')
        {
            p->prev_start = p->line_start;
            p->line_start = (p->pos);
            p->line_number += 1;
        }

        // Are we in a comment?
        if (p->ch == '%' && p->prev != '\\')
        {
            p->in_comment = true;
        }
        if (p->in_comment && p->ch == '\r')
        {
            p->in_comment = false;
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
        if (p->prev == '\r')
        {
            p->prev_start = p->line_start;
            p->line_start = (p->pos);
            p->line_number += 1;
        }
        
        // Are we in a comment?
        if (p->ch == '%' && p->prev != '\\')
        {
            p->in_comment = true;
        }
        if (p->in_comment && p->ch == '\r')
        {
            p->in_comment = false;
        }
    }
    return(false);
}


static bool getCommandType(BBLMTextIterator* iter, func_point_info* p, vector<UniChar>* c_id, int skip)
{
    // Skip requested characters to get to the relevant bit of the command
    for(int i=0; i < skip; i++)
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
    // * The title= key *must* be on the same line as the head command for the
    //   section to appear in the nav menu
    
    BBLMTextIterator iter(params);  // Iterator as supplied by calling code
    OSErr  result = noErr;          // Return check
    bool beyond_eof;                // Flag for getting out of nested parsers
    
    func_point_info point;
    point.ch = ' ';                 // The current character we're processing
    point.prev = ' ';               // The previous character
    point.pos = 0;                  // The current position in the file; we start at the first character
    point.line_start = 0;           // Position of the start of the current line
    point.line_number = 1;          // Start at first line
    point.in_comment = false;       // Track if we are in a comment to suppress folds
    
    // State stacks
    stack<UInt32> pend_funcs;    // Keep track of pending functions
    //stack<string> pending_types;    // Keep track of pending function types
    //stack<UInt32> pending_folds;    // Keep track of pending fold starts
    stack<fold_info> pend_folds;    // Keep track of pending folds

    int func_list_depth = 0;        // Keep track of visible funciton depth
    
    // General placeholder for fold_length calculations
    UInt32 fold_length = 0;    //
    
    // Comment Block Fold Handling
    UInt32 comm_block_pos = 0;      // Start of possible comment block
    int consec_comment_lines = 0;   // How many consecutive lines of comments to we have?
    UInt32 comm_fold_length = 0;    //

    
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
                // Set the fold to start after the first line
                if (consec_comment_lines == 1)
                {
                    comm_block_pos = point.line_start;
                }
                consec_comment_lines += 1;
            }
            else if (consec_comment_lines > 0 && point.line_start == point.pos)
            {
                if (consec_comment_lines > 2)
                {
                    comm_block_pos += 1;
                    comm_fold_length = point.pos - comm_block_pos - 1;
                    if (comm_fold_length > 0)
                    {
                        result = bblmAddFoldRange(&bblm_callbacks, comm_block_pos, comm_fold_length);
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
                fold_info curr_fold;        //
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
            if (iter.stricmp("\\start") == 0) // Check if we have a start command.
            {
                // We want to populate the info block as we go:
                //
                // info.fFunctionStart  = point.line_start;
                // info.fFunctionEnd    = func_stop;
                // info.fSelStart       = func_name_start; // title key
                // info.fSelEnd         = func_name_stop; //title key
                // info.fFirstChar      = func_start;
                // info.fKind           = kBBLMFunctionMark;
                // info.fIndentLevel    = func_list_depth;
                // info.fFlags          = 0;
                // info.fNameStart      = offset;
                // info.fNameLength     = func_name_length;
                
                
                BBLMProcInfo info;
                OSErr err;
                
                vector<UniChar> curr_id;
                vector<UniChar> curr_title;
                fold_info curr_fold;
                int TYPE_SKIP = 6;              // Number of characters to skip to get to command type
                bool show_fold = true;          // Stop from folding if in comment
                string cmd_type;                // Keep track of current command type (text after \start or \stop)
                
                // Track initial state
                if (point.in_comment) {show_fold = false;}
                if (getCommandType(&iter, &point, &curr_id, TYPE_SKIP)) break;
                cmd_type.assign(curr_id.begin(), curr_id.end());
                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), cmd_type) != valid_titles.end());

                // Set up info stanza as far as we can
                info.fFunctionStart = point.line_start;
                info.fFunctionEnd = point.line_start += 1; // We fix this in the /stop section
                info.fFirstChar = point.line_start;
                info.fKind = kBBLMFunctionMark;
                info.fFlags = 0;
                
                // Handle Folds
                curr_fold.name = cmd_type;
                curr_fold.start = point.pos;
                
                if (cmd_type == "text" && point.line_number > 4)
                {
                    // Close off preamble fold, end is linestart - 1
                    int fold_start = 0;
                    fold_length = point.prev_start - 1;
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
                    // Argh; state machine to handle parsing this?
                    
                    beyond_eof = false;
                    if (skipWhiteSpace(&iter, &point)) break;
                    if (point.ch == '[')
                    {
                        // We have an option block
                        // Scan forward until close of option block
                        // TODO: find a more graceful way to handle open parameter blocks in this context!
                        while (point.ch != ']' && point.ch != '\r')
                        {
                            // Look for a title key
                            if (iter.strcmp("title") == 0)
                            {
                                // scan forward to {
                                while (point.prev != '{' && point.ch != '\r')
                                {
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                info.fSelStart = point.pos;
                                while(*iter != '}' && *iter != ']' && *iter != '\r') // People do not want multi-line titles
                                {
                                    curr_title.push_back(point.ch);
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                info.fSelEnd = point.pos;
                                while (point.prev != ']' && point.ch != '\r')
                                {
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                // We have a better place to start the fold
                                curr_fold.start = point.pos;
                                
                                if (beyond_eof) {break;}
                            }
                            if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                        } //End of option block scan
                        

                    } // End of option block check
                    
                    // We didn't find a title, so set an appropriate placeholder.
                    if (curr_title.empty())
                    {
                        string dummy_header_text = "NO TITLE";
                        copy(dummy_header_text.begin(), dummy_header_text.end(), back_inserter(curr_title));
                        info.fSelStart = point.line_start - 1;
                        info.fSelEnd = point.pos + 1;
                    }
                    
                    // We have a title, now: we should have everything we need
                    // Prepare for the token
                    UInt32 func_title_length;
                    UInt32 offset = 0;
                    func_title_length = curr_title.size();
                    UniChar *ident = &curr_title[0];
                    // Set up the token
                    err = bblmAddTokenToBuffer(&bblm_callbacks, params.fFcnParams.fTokenBuffer, ident, func_title_length, &offset);
                    if (err)
                    {
                        return err;
                    }
                    
                    // Set up any remaining bits of the stanza
                    info.fIndentLevel = func_list_depth;
                    info.fNameStart = offset;
                    info.fNameLength = func_title_length;
                    
                    // Add function
                    UInt32 func_index = 0;
                    err = bblmAddFunctionToList(&bblm_callbacks, params.fFcnParams.fFcnList,info, &func_index);
                    if (err)
                    {
                        return err;
                    }
                    pend_funcs.push(func_index);
                    func_list_depth += 1;
                    
                    // Catch EOF errors and send them on
                    if (beyond_eof) {break;}
                
                } // end if is_known_type
                
                // Set fold with any updated values
                if (show_fold) {pend_folds.push(curr_fold);}
            }
            if (iter.stricmp("\\stop") == 0) // Check if we have a stop command.
            {
                BBLMProcInfo info;
                OSErr err;                  // Return check
                vector<UniChar> curr_id;    // Text of current command
                UInt32 curr_func_idx;       // Index of current function
                fold_info curr_fold;        // Fold from the top of the fold stack
                int TYPE_SKIP = 5;          // Number of characters to skip to get to command type
                string cmd_type;            // temp string of current command
                bool show_fold = true;      // Stop from folding if in comment

                // Track initial state
                if (point.in_comment) {show_fold = false;}
                if (getCommandType(&iter, &point, &curr_id, TYPE_SKIP)) break;
                cmd_type.assign(curr_id.begin(), curr_id.end());
                bool is_known_type = (find(valid_titles.begin(), valid_titles.end(), cmd_type) != valid_titles.end());
                
                // Handle Folds
                if (show_fold && !pend_folds.empty())
                {
                    curr_fold = pend_folds.top();
                    if (curr_fold.name.compare(cmd_type) == 0 )
                    {
                        pend_folds.pop();
                        fold_length = point.pos - curr_fold.start - cmd_type.length() - TYPE_SKIP;
                        if (fold_length > 0)
                        {
                            err = bblmAddFoldRange(&bblm_callbacks, curr_fold.start, fold_length);
                            if (err)
                            {
                                return err;
                            }
                        }
                    }
                } // End fold handling
                
                // handle /stoptext fold
                if (cmd_type == "text")
                {
                    // Begin postamble fold
                    fold_info end_fold;
                    end_fold.start = point.pos +1;
                    end_fold.name = "ENDFOLD";
                    pend_folds.push(end_fold);
                } // end /stoptext fold
                
                if (is_known_type && !pend_funcs.empty())
                {
                    curr_func_idx = pend_funcs.top();
                    pend_funcs.pop();
                    func_list_depth--;
                    
                    err = bblmGetFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
                    if (err)
                    {
                        return err;
                    }
                    while (isalnum(*iter))
                    {
                        if (skipChars(&iter, &point, 1)) break;
                    }
                    info.fFunctionEnd = point.pos;
                    err = bblmUpdateFunctionEntry(&bblm_callbacks,params.fFcnParams.fFcnList, curr_func_idx, info);
                    if (err)
                    {
                        return err;
                    }
                }
                
                
            }
            
        } // End of test for start of command
        if (skipChars(&iter, &point, 1)) break;
    } // End of Main While Loop
    
    if (!pend_folds.empty())
    {
        OSErr err;
        fold_info curr_fold;
        curr_fold = pend_folds.top();
        fold_length = point.pos - curr_fold.start;
        if (fold_length > 0 && curr_fold.name == "ENDFOLD")
        {
            err = bblmAddFoldRange(&bblm_callbacks, curr_fold.start, fold_length);
            if (err)
            {
                return err;
            }
        }
    }
    
    // Clean up
    while (!pend_funcs.empty())
    {
        pend_funcs.pop();
    }
    while (!pend_folds.empty())
    {
        pend_folds.pop();
    }
    
    return result;
}