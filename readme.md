
BBEdit Language Module for ConTeXt Authoring

Intended for BBEdit v11, for use with ConTeXt MkIV.

Created by Paul Mazaitis.

# Introduction

This is a compiled BBEdit language module to help with creating .tex files for the ConTeXt typesetting system.

The language module supports the following features:

 * Navigation by heading titles (including titles from user-defined heads).
 * Navigation by callouts (TODO:, FIXME:, etc.)
 * Navigation to files referenced by the \environment command.
 * Folding text within balanced \start and \stop commands.
 * Syntax coloring of text, comments, commands, command parameters, and command options.
 * Keyword support.
 * Command completion.

# Navigation by Heading Titles

This language module supports navigation of ConTeXt documents by heading titles. When encountering headings in the document, the module will populate the BBEdit function navigation menu with the text specified in the title={} keyval (or a placeholder if missing). Logical depth of the head is indicated by indent in the menu.

This language module lists headings defined by /setuphead in the function navigation menu.

# Navigation by Callouts

This language module supports navigation of ConTeXt documents by callouts in the text. These callouts are supported:

 * FIXME:
 * TODO:
 * REVIEW:
 * ???:
 * !!!:
 * NOTE: 
 
Callouts must be in a commented region and include a space after the colon to be recognized by the language module. Recognized callouts are added to the function navigation menu with an extra level of intent.

# Files Referenced With \environment

This language module looks for files referenced by \environment commands, and adds them to the BBEdit navigational drop-down for include files.

At the moment, the language module searches upward through the directory structure for the referenced environment file with no extension, or with the extensions *.tex*, *.mkiv*, or *.mkvi*. If the file is found, the file is loaded.

If no file matching these criteria is found, the file is created and loaded in the same directory as the file containing the /environment command.

# Folding Text

This language module supports the following folds:

 * Folds from balanced pairs of /start and /stop commands
 * A fold from the beginning of the document to /starttext, if applicable
 * A fold from /stoptext to the end of the document, if applicable
 * Folds for comment blocks of three or more lines, with the first line visible

# Coloring Syntax

This language module identifies and colors five types of text:

 * Plain text
 * Commands
 * Command Parameters (square brackets and contents)
 * Command Options (curly brackets only)
 * Comments

Colors can be customized in the Text Colors preference pane under the group name **ConTeXt**.

# Keywords

This language module can use the file Resources/context-keywords.txt in the BBLM bundle to indicate keywords. context-keywords.txt is a plain text file, one keyword per line.

# Command Completion

This language module supports command completion. This module uses the file Resources/context-commands-en.txt in the BBLM bundle to indicate commands.context-commands-en.txt is a plain text file, one command per line. Commands should include the backslash.

A version of this file can be generated with mtxrun:

> mtxrun -script interface —text

# Future Work

 * Improve include file search to support project structure (http://wiki.contextgarden.net/Project_structure).

# Licensing

The author makes no warranties with regard to this work, and disclaims liability for all uses of this work, to the fullest extent permitted by applicable law.

The source files for this language module are in the public domain.

The header files in "SDK Headers" are taken from the BBEdit Development Kit,
and are copyright Bare Bones Software, Inc.
  
  http://www.barebones.com/support/develop/

# Thanks

...go to Kathryn, Patrick, Andrew, and Thomas.
