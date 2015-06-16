
BBEdit Language Module for ConTeXt Authoring

Intended for BBEdit v11.

Created by Paul Mazaitis <paul@mazaitis.org>

# Introduction

This is a compiled BBEdit language module to help with creating .tex files for the ConTeXt typesetting system.

The language module supports the following features:

 * Navigation by heading titles (including titles from user-defined heads).
 * Navigation by callouts (TODO:, FIXME:, etc.)
 * Navigation to files referenced by the \environment command.
 * Folding text within balanced \start and \stop commands.
 * Syntax coloring of text, comments, commands, command parameters, and command options.

# Navigation by Heading Titles

This language module supports navigation of ConTeXt documents by heading titles. When encountering headings in the document, the module will populate the BBEdit function navigation menu with the text specified in the title={} keyval (or a placeholder if missing). Logical depth of the head is indicated by indent in the menu.

This language module lists headings defined by /setuphead in the function navigation menu.

# Navigation by Callouts

This language module supports navigation of ConTeXt documents by heading titles. These callouts are supported:

 * FIXME:
 * TODO:
 * REVIEW:
 * ???:
 * !!!:
 * NOTE: 
 
Callouts must include a space after the colon to be recognized by the language module. Recognized callouts are added to the function navigation menu without indent.

# Files Referenced With \environment

This language module looks for files referenced by \environment commands, and adds them to the navigational drop-down for include files in BBEdit.

At the moment, the language module isn't terribly clever about this: it doesn't do any checking to see if the referenced file has a reasonable name, extension, etc. If the referenced file is valid, the file can be loaded into the editor via the include menu. BBEdit does not support searching for files by multiple extensions, so accessing files this way will only work if the complete and correct file name is used with the \environment command.

# Folding Text

This language module supports the following folds:

 * Folds from balanced pairs of /start and /stop commands
 * A fold from the beginning of the document to /starttext, if applicable
 * A fold from /stoptext to the end of the document, if applicable

# Coloring Syntax

This language module identifies and colors five types of text:

 * Plain text
 * Commands
 * Command Parameters (square brackets)
 * Command Options (curly brackets)
 * Comments

Colors can be customized in the Text Colors preference pane under the group name **ConTeXt**.

# Licensing

The author makes no warranties with regard to this work, and disclaims liability for all uses of this work, to the fullest extent permitted by applicable law.

The source files for this language module are in the public domain.

The header files in "SDK Headers" are taken from the BBEdit Development Kit,
and are copyright Bare Bones Software, Inc.
  
  http://www.barebones.com/support/develop/

# Thanks

...go to Kathryn, Patrick, and Andrew.
