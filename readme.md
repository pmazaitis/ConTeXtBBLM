
BBEdit Language Module for ConTeXt Authoring

Intended for BBEdit v11, for use with ConTeXt MkIV.

Created by Paul Mazaitis.

# Introduction

This is a compiled BBEdit language module to help with creating .tex files for the ConTeXt typesetting system.

The language module supports the following features:

 * Navigation by heading titles (including titles from user-defined heads).
 * Navigation by callouts (TODO:, FIXME:, etc.)
 * Navigation to files referenced by the project structure and file inclusion commands.
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
 
Callouts must be in a commented region and include a space after the colon to be recognized by the language module. Recognized callouts are added to the function navigation menu with an extra level of indent.

# Files Referenced With Project Structure and File Inclusion Commands

This language module looks for files referenced by project and file inclusion commands, and adds them to the BBEdit navigational drop-down for include files.

At the moment, the language module searches for the referenced file with the extensions *.tex*, *.mkiv*, or *.mkvi*. The language module will search recursively downward in the filesystem from the parent directory of the referencing file. The language module will perform a similar search rooted in TEXMFHOME; if the language module can't figure out where TEXMFHOME is, the language module will use ~/texmf as TEXMFHOME if ~/texmf exists. If the referenced file is found, the file is loaded.

If no file matching these criteria is found, the language module will ask the user if they wish to create the file; if the user does so, the language module will open a save dialog so that the user may choose where the new file should be created.

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

This language module supports command completion. This module uses the file Resources/context-commands-en.txt in the BBLM bundle to indicate commands. context-commands-en.txt is a plain text file, one command per line. Commands should include the backslash.

A version of this file can be generated with mtxrun:

> mtxrun -script interface —text

...although some commands appear to be missing from this version of the interface. This language module ships with an amended interface context-commands-en.txt.

# Future Work

 * (None planned with this version)

# Licensing

The author makes no warranties with regard to this work, and disclaims liability for all uses of this work, to the fullest extent permitted by applicable law.

The source files for this language module are in the public domain.

The header files in "SDK Headers" are taken from the BBEdit Development Kit,
and are copyright Bare Bones Software, Inc.
  
  http://www.barebones.com/support/develop/

# Thanks

...go to Kathryn, Patrick, Andrew, and Thomas.
