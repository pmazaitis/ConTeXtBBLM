//
//  scan_functions.mm
//
//  BBedit Language Module for ConTeXt.
//
//  Created by Paul Mazaitis.
//
//  See https://github.com/pmazaitis/ConTeXtBBLM

//
// TODO: special case naked /start nad /stop commands - supress folding in these cases.

#include <string>
#include <stack>
#include <vector>

#include "context.h"

#include "syslog.h"

#define MAX_PARAM_SIZE 255
#define MAX_RANK 4095

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
    UInt32 line_number = 0;     // Line number where the fold starts
    string type = "";           // Command name of the fold
    int rank = 0;               // Rank of fold for error recovery
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

//static bool skipToWhiteSpace(BBLMTextIterator* iter, func_point_info* p)
//{
//    while (!isspace(p->ch))
//    {
//        p->prev = p->ch;
//        (*iter)++;
//        (p->pos)++;
//        
//        if (iter->InBounds())
//        {
//            p->ch = **iter;
//        }
//        else
//        {
//            return(true);
//        }
//        
//        // Do we have a new line?
//        if (p->prev == '\r')
//        {
//            p->prev_start = p->line_start;
//            p->line_start = (p->pos);
//            p->line_number += 1;
//        }
//        
//        // Are we in a comment?
//        if (p->ch == '%' && p->prev != '\\')
//        {
//            p->in_comment = true;
//        }
//        if (p->in_comment && p->ch == '\r')
//        {
//            p->in_comment = false;
//        }
//    }
//    return(false);
//}

static bool rollBack(BBLMTextIterator* iter, func_point_info* p)
{
    (*iter)--;
    (p->pos)--;
    
    if (**iter == '\r')
    {
        p->line_number -= 1;
    }
    
    
    if (iter->InBounds())
    {
        p->ch = **iter;
    }
    else
    {
        return(true);
    }
    return(false);
}


static bool getCommandNameAndType(BBLMTextIterator* iter, func_point_info* p, vector<UniChar>* c_name, vector<UniChar>* c_type, int skip)
{
    // Skip requested characters to get to the relevant bit of the command
    for(int i=0; i < skip; i++)
    {
        c_name->push_back(p->ch);
        if (skipChars(iter, p, 1)) return true;
    }
    // Collect Characters until we get to the end of the command
    while (isalnum(**iter) || **iter == '\\')
    {
        c_name->push_back(p->ch);
        c_type->push_back(p->ch);
        if (skipChars(iter, p, 1)) return true;
    }
    return(false);
}

static bool inParamBlock(BBLMTextIterator* iter, func_point_info* p, int param_char_count)
{
    // If we hit the character limit, return true.
    if (param_char_count > MAX_PARAM_SIZE)
    {
        return false;
    }
    
    // If we encounter anything that might need to be processed:
    // * a command start ('\')
    // * callout
    // ...return true.
    if (p->ch == '\\')
    {
        return false;
    }
    if (iter->strcmp("FIXME: ") == 0 ||
        iter->strcmp("TODO: ") == 0 ||
        iter->strcmp("REVIEW: ") == 0 ||
        iter->strcmp("???: ") == 0 ||
        iter->strcmp("!!!: ") == 0 ||
        iter->strcmp("NOTE: ") == 0 )
    {
        return false;
    }

    // No conditions found, funciton block not over
    return true;
}

static int getTypeRank(string str_type)
{
    NSString *curr_type = [NSString stringWithUTF8String:str_type.c_str()];
    
    NSDictionary * type_ranks = [[NSDictionary alloc] initWithObjectsAndKeys:
                                 [NSNumber numberWithInt:0], @"component",
                                 [NSNumber numberWithInt:1], @"text",
                                 [NSNumber numberWithInt:2], @"part",
                                 [NSNumber numberWithInt:2], @"frontmatter",
                                 [NSNumber numberWithInt:2], @"bodymatter",
                                 [NSNumber numberWithInt:2], @"backmatter",
                                 [NSNumber numberWithInt:2], @"appendices",
                                 [NSNumber numberWithInt:3], @"chapter",
                                 [NSNumber numberWithInt:3], @"title",
                                 [NSNumber numberWithInt:4], @"section",
                                 [NSNumber numberWithInt:4], @"subject",
                                 [NSNumber numberWithInt:5], @"subsection",
                                 [NSNumber numberWithInt:5], @"subsubject",
                                 [NSNumber numberWithInt:6], @"subsubsection",
                                 [NSNumber numberWithInt:6], @"subsubsubject",
                                 [NSNumber numberWithInt:7], @"subsubsubsection",
                                 [NSNumber numberWithInt:7], @"subsubsubsubject",
                                 [NSNumber numberWithInt:8], @"subsubsubsubsection",
                                 [NSNumber numberWithInt:8], @"subsubsubsubsubject",
                                 nil];

    // And set special ranking values for heirarchy in the TABLE environment
    if (str_type == "TABLE")
    {
        return MAX_RANK - 2;
    }
    
    if (str_type == "TR")
    {
        return MAX_RANK - 1;
    }
    
    if([[type_ranks allKeys] containsObject:curr_type])
    {
        int curr_rank = [[type_ranks objectForKey:curr_type] intValue];
        return curr_rank;
    }
    else
    {
        return MAX_RANK;
    }

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
    // The scanner will look for a set list of callouts in comment regions, and add
    // these callouts to the function drop-down when found. Callouts are not indented.
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
    stack<fold_info> pend_folds;    // Keep track of pending folds

    // Keep track of visible funciton depth
    int func_list_depth = 0;
    
    // General placeholder for fold_length calculations
    UInt32 fold_length = 0;    //
    // Keep track of fold depth, to error check for missing fold anchors
    //UInt32 curr_fold_depth =0;
    
    // Comment Block Fold Handling
    UInt32 comm_block_pos = 0;      // Start of possible comment block
    int consec_comment_lines = 0;   // How many consecutive lines of comments to we have?
    UInt32 comm_fold_length = 0;    //

    // TODO: use a block in the Info.plist to supply these values.
    vector<string> valid_title_types = {    "part",
                                            "chapter",
                                            "title",
                                            "section",
                                            "subject",
                                            "subsection",
                                            "subsubject",
                                            "subsubsection",
                                            "subsubsubject",
                                            "subsubsubsection",
                                            "subsubsubsubject",
                                            "subsubsubsubsection",
                                            "subsubsubsubsubject"};
    


    
    iter += point.pos; // TODO: do we ever want to get this value from the params block?
    
    point.ch = *iter;
    point.line_start = 0;
    if (point.ch == '%')
    {
        point.in_comment = true;
    }
    
    while(true) // We test for our out of bounds conditions when skipping characters
    {
        // Test for Callouts in Comments
        if (point.in_comment)
        {
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
                
                int callout_depth = 0;
                
                if (func_list_depth != 0)
                {
                    callout_depth = func_list_depth + 1;
                }
                
                // Set up the info stanza
                info.fFunctionStart = func_start;
                info.fFunctionEnd = func_stop;
                info.fSelStart = func_start;
                info.fSelEnd = func_stop;
                info.fFirstChar = func_start;
                info.fKind = callout_kind;
                info.fIndentLevel = callout_depth;
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
            // We want to test for any of the product commands:
            // * \environment
            // * \project
            // * \product
            // * \component
            //
            // ...as well as any of the straight inclusion commands:
            // * \input         (explict filename)
            // * \ReadFile      (PathSearch, noop for missing file)
            // * \readfile      (PathSearch)
            // * \readlocfile   (current path)
            // * \readsysfile   (current path, obeys tex search)
            // * \readfixfile   (specified path, backtracking)

            
            
            if (iter.strcmp("\\environment") == 0 ||
                iter.strcmp("\\project") == 0 ||
                iter.strcmp("\\product") == 0 ||
                iter.strcmp("\\component") == 0
                )
            {
                UInt32 func_start = point.pos;
                UInt32 func_stop = 0;
                UInt32 func_name_start = 0;
                UInt32 func_name_stop = 0;
                BBLMProcInfo info;
                OSErr err;
                UInt32 TYPE_SKIP = 0;
                
                
                vector<UniChar> curr_name;    // Name of current command
                vector<UniChar> curr_type;    // Type of current command
                vector<UniChar> curr_include;
                
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
                if (skipWhiteSpace(&iter, &point)) break;
                
                string cmd_name;
                cmd_name.assign(curr_name.begin(), curr_name.end());
                
                if (cmd_name == "\\environment" ||
                    cmd_name == "\\project" ||
                    cmd_name == "\\product" ||
                    cmd_name == "\\component")
                {
                    func_name_start = point.pos;
                    
                    while (!isspace(*iter)) {
                        // Collect characters in the referenced file until we get to whitespace
                        curr_include.push_back(point.ch);
                        if (skipChars(&iter, &point, 1)) break;
                    }
                    
                    func_stop = point.pos;
                    func_name_stop = point.pos;
                    
                    // ident is the first Unichar of curr_include
                    UniChar *ident = &curr_include[0];
                    
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
            }
            
            if (iter.strcmp("\\input") == 0 ||
                iter.strcmp("\\ReadFile") == 0 ||
                iter.strcmp("\\readfile") == 0 ||
                iter.strcmp("\\readlocfile") == 0 ||
                iter.strcmp("\\readsysfile") == 0 ||
                iter.strcmp("\\readfixfile") == 0
                )
            {
                UInt32 func_start = point.pos;
                UInt32 func_stop = 0;
                UInt32 func_name_start = 0;
                UInt32 func_name_stop = 0;
                BBLMProcInfo info;
                OSErr err;
                UInt32 TYPE_SKIP = 0;
                
                vector<UniChar> curr_name;    // Name of current command
                vector<UniChar> curr_type;    // Type of current command
                vector<UniChar> curr_include;
                
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
         
                string cmd_name;
                cmd_name.assign(curr_name.begin(), curr_name.end());
                
                if (cmd_name == "\\input" ||
                    cmd_name == "\\ReadFile" ||
                    cmd_name == "\\readfile" ||
                    cmd_name == "\\readlocfile" ||
                    cmd_name == "\\readsysfile" ||
                    cmd_name == "\\readfixfile"
                    )
                {
                    // Find the start of the brackets
                    while (point.ch != '{' && point.ch != '\r')
                    {
                        if (skipChars(&iter, &point, 1)) break;
                    }
                    
                    // Eat the {
                    if (skipChars(&iter, &point, 1)) break;
                    
                    func_name_start = point.pos;
                    
                    int param_char_count = 0;
                    // Find the end of the brackets
                    while (inParamBlock(&iter, &point, param_char_count) && point.ch != '}') {
                        // Collect characters in the referenced file until we get to whitespace
                        curr_include.push_back(point.ch);
                        if (skipChars(&iter, &point, 1)) break;
                    }
                    
                    func_stop = point.pos;
                    func_name_stop = point.pos;
                    
                    // ident is the first Unichar of curr_environment
                    UniChar *ident = &curr_include[0];
                    
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
                valid_title_types.push_back(new_head_definition); // Add our new definition to the list of valid heads
            }
            if (!point.in_comment && (iter.strcmp("\\bTABLE") == 0 || iter.strcmp("\\bTR") == 0))
            {
                vector<UniChar> curr_name;    // Name of current command
                vector<UniChar> curr_type;    // Type of current command
                fold_info curr_fold;        //
                UInt32 TYPE_SKIP = 2;          // Number of characters to skip to get to command type
                
                curr_fold.start = point.line_start;
                // Pull the command type into a vector
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
                // Set the values for the fold, and add it to the stack
                curr_fold.type.assign(curr_type.begin(), curr_type.end());
                curr_fold.start += curr_fold.type.length() + TYPE_SKIP;
                curr_fold.line_number = point.line_start;
                curr_fold.rank = MAX_RANK;
                pend_folds.push(curr_fold);
            }
            if (!point.in_comment && (iter.strcmp("\\eTABLE") == 0 || iter.strcmp("\\eTR") == 0))
            {
                OSErr err;                  // Return check
                vector<UniChar> curr_name;    // Name of current command
                vector<UniChar> curr_type;    // Type of current command
                fold_info curr_fold;        // Fold from the top of the fold stack
                UInt32 TYPE_SKIP = 2;          // Number of characters to skip to get to command type
                string tt;                  // temp string of current command
               
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
                tt.assign(curr_type.begin(), curr_type.end());
                
                if ( !pend_folds.empty())
                {
                    curr_fold = pend_folds.top();
                    
                    if (curr_fold.type.compare(tt) == 0 )
                    {
                        pend_folds.pop();
                        fold_length = point.pos - curr_fold.start - (UInt32)tt.length() - TYPE_SKIP;
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
                // info.fFunctionStart
                // info.fFunctionEnd
                // info.fSelStart
                // info.fSelEnd
                // info.fFirstChar
                // info.fKind
                // info.fIndentLevel
                // info.fFlags
                // info.fNameStart
                // info.fNameLength
                
                
                BBLMProcInfo info;
                OSErr err;
                
                vector<UniChar> curr_name;    // Name of current command
                vector<UniChar> curr_type;    // Type of current command
                vector<UniChar> curr_title;
                fold_info curr_fold;
                int TYPE_SKIP = 6;              // Number of characters to skip to get to command type
                bool show_fold = true;          // Stop from folding if in comment
                string cmd_name;                // Keep track of current command
                string cmd_type;                // Keep track of current command type (text after \start or \stop)
                
                // Track initial state
                if (point.in_comment) {show_fold = false;}
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
                
                cmd_name.assign(curr_name.begin(), curr_name.end());
                cmd_type.assign(curr_type.begin(), curr_type.end());
                if (cmd_name == "\\start") {show_fold = false;}
                bool is_known_type = (find(valid_title_types.begin(), valid_title_types.end(), cmd_type) != valid_title_types.end());

                // Set up info stanza as far as we can
                info.fFunctionStart = point.line_start;
                info.fFunctionEnd = point.line_start += 1; // We fix this in the /stop section
                info.fFirstChar = point.line_start;
                info.fKind = kBBLMFunctionMark;
                info.fFlags = 0;
                
                // Handle Folds
                //
                // We first want to check and see if we're seeing a type of the same or higher rank; if we're
                // starting a new parent we want to tie off the fold.
                
                if (!pend_folds.empty())
                {
                    fold_info prev_fold = pend_folds.top();
                    if (getTypeRank(cmd_type) <= prev_fold.rank)
                    {
                        // We've missed a close, and need to tie off the fold.
                        fold_length = point.pos - prev_fold.start - (UInt32)cmd_type.length() - TYPE_SKIP;
                        if (fold_length > 0)
                        {
                            err = bblmAddFoldRange(&bblm_callbacks, prev_fold.start, fold_length);
                            if (err)
                            {
                                return err;
                            }
                        }
                        // Pop the garbage fold value off of the pending fold stack.
                        pend_folds.pop();
                        // Log an error
                        syslog(LOG_WARNING, "ConTeXt BBLM Warning: Problem fold %s at line %d, unmatched start command at line %d.", cmd_name.c_str(), (unsigned int)point.line_number, (unsigned int)prev_fold.line_number);
                    }
                }
                
                // Then, set up info for the current fold
                curr_fold.type = cmd_type;
                curr_fold.start = point.pos;
                curr_fold.line_number = point.line_number;
                curr_fold.rank = getTypeRank(cmd_type);
                
                if (cmd_name == "\\starttext" && point.line_number > 4 && show_fold)
                {
                    // Close off preamble fold, end is linestart - 1
                    int fold_start = 0;
                    fold_length = point.line_start - 2;
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
                    beyond_eof = false;
                    if (skipWhiteSpace(&iter, &point)) break;
                    if (point.ch == '[')
                    {
                        int param_char_count = 0;
                        // We have an option block
                        // Scan forward until close of option block
                        
                        while (inParamBlock(&iter, &point, param_char_count) && point.ch != ']')
                        {
                            // Increase the count so we can guess if we have a malformed command parameter block
                            param_char_count += 1;
                            // Look for a title key
                            if (iter.strcmp("title") == 0)
                            {
                                // scan forward to {
                                while (inParamBlock(&iter, &point, param_char_count) && point.prev != '{' )
                                {
                                    param_char_count += 1;
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                info.fSelStart = point.pos;
                                // Get the title text (we do not expect the title text to include line breaks)
                                while(inParamBlock(&iter, &point, param_char_count) && *iter != '}' && *iter != ']' && *iter != '\r')
                                {
                                    param_char_count += 1;
                                    curr_title.push_back(point.ch);
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                info.fSelEnd = point.pos;
                                if (rollBack(&iter, &point)) {beyond_eof = true; break;}
                                while (inParamBlock(&iter, &point, param_char_count) && point.ch != ']')
                                {
                                    param_char_count += 1;
                                    if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                                }
                                // We have a better place to start the fold
                                curr_fold.start = point.pos + 1;
                                
                                if (beyond_eof) {break;}
                            }
                            if (skipChars(&iter, &point, 1)) {beyond_eof = true; break;}
                        } //End of option block scan

                        // Reprocess the current character
                        if (rollBack(&iter, &point)) {beyond_eof = true; break;}

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
                    func_title_length = (UInt32)curr_title.size();
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
                vector<UniChar> curr_name;  // Text of current command
                vector<UniChar> curr_type;  // Text of current command
                UInt32 curr_func_idx;       // Index of current function
                fold_info pend_fold;        // Fold from the top of the fold stack
                int TYPE_SKIP = 5;          // Number of characters to skip to get to command type
                string cmd_name;            // temp string of current command name
                string cmd_type;            // temp string of current command type
                bool show_fold = true;      // Stop from folding if in comment

                // Track initial state
                if (point.in_comment) {show_fold = false;}
                if (getCommandNameAndType(&iter, &point, &curr_name, &curr_type, TYPE_SKIP)) break;
                cmd_name.assign(curr_name.begin(), curr_name.end());
                cmd_type.assign(curr_type.begin(), curr_type.end());
                if (cmd_name == "\\stop") {show_fold = false;}
                bool is_known_type = (find(valid_title_types.begin(), valid_title_types.end(), cmd_type) != valid_title_types.end());
                
                // Handle Folds
                //
                // Keep popping the stack until the rank of the prev_fold is greater than or equal to current stop
                fold_info prev_fold;
                if (!pend_folds.empty())
                {
                    prev_fold = pend_folds.top();
                }
                if (show_fold)
                {
                    while (getTypeRank(cmd_type) <= prev_fold.rank && !pend_folds.empty())
                    {
                        // We've missed a close, and need to tie off the fold.
                        fold_length = point.pos - prev_fold.start - (UInt32)cmd_type.length() - TYPE_SKIP;
                        if (fold_length > 0)
                        {
                            err = bblmAddFoldRange(&bblm_callbacks, prev_fold.start, fold_length);
                            if (err)
                            {
                                return err;
                            }
                        }
                        // Pop the garbage fold value off of the pending fold stack.
                        pend_folds.pop();
                        if (!pend_folds.empty())
                        {
                            prev_fold = pend_folds.top();
                        }
                        else
                        {
                            break;
                        }
                    }
                } // End fold handling
                
                // handle /stoptext fold
                if (cmd_name == "\\stoptext")
                {
                    // Begin postamble fold
                    fold_info end_fold;
                    end_fold.start = point.pos +1;
                    end_fold.type = "ENDFOLD";
                    pend_folds.push(end_fold);
                } // end /stoptext fold
                
                
                if (is_known_type && !pend_funcs.empty())
                {
                    curr_func_idx = pend_funcs.top();
                    pend_funcs.pop();
                    func_list_depth -= 1;
                    
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
        if (fold_length > 0 && curr_fold.type == "ENDFOLD")
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