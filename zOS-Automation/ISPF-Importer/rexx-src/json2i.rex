/* REXX ***************************************************************/
/*                                                                    */
/*  Copyright 2023 IBM Corp.                                          */
/*                                                                    */
/*  Licensed under the Apache License, Version 2.0 (the "License");   */
/*  you may not use this file except in compliance with the License.  */
/*  You may obtain a copy of the License at                           */
/*                                                                    */
/*  http://www.apache.org/licenses/LICENSE-2.0                        */
/*                                                                    */
/*  Unless required by applicable law or agreed to in writing,        */
/*  software distributed under the License is distributed on an       */
/*  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,      */
/*  either express or implied. See the License for the specific       */
/*  language governing permissions and limitations under the License. */
/*                                                                    */
/**********************************************************************/
/* Name:      JSON2I  - JSON to ISPF table converter                  */
/*                                                                    */
/* Function:  This program converts a JSON file with a specific       */
/*            structure into an ISPF table                            */
/*                                                                    */
/* Requirements:                                                      */
/*            Program needs ISPF environment as it uses ISPF table    */
/*            service to write JSON data into ISPF table.             */
/*                                                                    */
/*            JSON file must be encoded in EBCDIC (IBM-1047) or       */
/*            in UTF-8.                                               */
/*                                                                    */
/******************************* INPUT  *******************************/
/*                                                                    */
/* Parameters:                                                        */
/*            1.  FILEPATH=[Input file path (in USS)] - Mandatory     */
/*            2.  DSN=[Name of the fully qualified PDS where the      */
/*                table needs to be loaded] - optional. If not        */
/*                specified, program tries to read it from the JSON   */
/*                root object                                         */
/*            3.  TBLNAM=[Output ISPF table name] - optional. If not  */
/*                specified, program tries to read it from the JSON   */
/*                root object                                         */
/*            4.  TBLENC=[Encoding type of the output ISPF table] -   */
/*                optional. If not specified, IBM-1047 is the default */
/*            5.  ([Options ] - optional. Currently only the REPLACE  */
/*                and FORCE parameters are supported                  */
/*                                                                    */
/* Expected format of parameters:                                     */
/*            1.  Full path of the input JSON file - case sensitive   */
/*                For example: FILEPATH=/u/user/test.json             */
/*            2.  Fully qualified data set name                       */
/*                For example: DSN='USER.TABLE.LIB'                   */
/*            3.  Maximum 8 char long table name                      */
/*                For example: TBLNAM=AAATABLE                        */
/*            4.  Desired table encoding type                         */
/*                For example: TBLENC=IBM-500                         */
/*            5.  Options: must begin with an opening parenthesis.    */
/*                REPLACE or REPL - ISPF table will be replaced if    */
/*                                  there is already a table with the */
/*                                  same name and the same structure  */
/*                                  (keys and column names) as the    */
/*                                  table to be imported              */
/*                FORCE           - ISPF table will be replaced       */
/*                                  regardless of whether the         */
/*                                  structure is the same as the      */
/*                                  existing one or not               */
/*                For example: (REPL or (REPL FORCE                   */
/*                                                                    */
/******************************* OUTPUT *******************************/
/*                                                                    */
/*            The extracted data from JSON is written into the output */
/*            ISPF table within the defined table library.            */
/*                                                                    */
/*            RC 0          = Good completion                         */
/*            RC 1          = Missing mandatory program parameter     */
/*            RC < 0 or > 1 = Something went wrong, please check      */
/*                            the output error message                */
/*                                                                    */
/*************************** CHANGE HISTORY ***************************/
/* Date      Name                    Revision                         */
/* --------  ----------------------  -------------------------------- */
/* 22/10/22  Akos Hosszu             Initial release                  */
/* 20/01/23  Akos Hosszu             Introduced UTF-8 as input JSON   */
/*                                   encoding type, user defined      */
/*                                   target (table) encoding type and */
/*                                   the logic behind the conversion  */
/*                                   from detected JSON encoding type */
/*                                   to user defined target encoding  */
/* 24/01/23  Sushmita Das            Re-structured the program        */
/*                                   argument parsing method, added   */
/*                                   TBLENC parameter as a new        */
/*                                   program argument and handled if  */
/*                                   dsnParm parameter is not in      */
/*                                   quotes                           */
/* 27/01/23  Akos Hosszu             Refined the code, added more     */
/*                                   error handlers, introduced new   */
/*                                   functions to check the target    */
/*                                   table structure before replacing */
/*                                   and added related FORCE option   */
/*                                   as new program argument          */
/*                                                                    */
/**********************************************************************/
parse arg parms                           /* parse program parameters */
call syscalls 'ON'                                 /* enable SYSCALLS */
msgStat = MSG("on")                          /* enable TSO/E messages */
finalRC = 0
signal on Syntax

/* Process program parameters *****************************************/
filePath = ''
dsnParm = ''
tblnamParm = ''
userTableEnc = ''
opts = ''

/* Run a loop for each of the word inside parms                       */
numOfParm = STRIP(WORDS(parms))
pc = 1
do while(pc <= numOfParm)
 parm.pc = STRIP(WORD(parms,pc))
 if (POS('FILEPATH',TRANSLATE(parm.pc)) = 0) then do
  parm.pc = TRANSLATE(parm.pc)
 end
 select
  when (POS('FILEPATH',TRANSLATE(parm.pc)) > 0) then do
   filePath = STRIP(SUBSTR(parm.pc,POS('=',parm.pc)+1))
  end
  when (POS('DSN',parm.pc) > 0) then do
   dsnParm = STRIP(SUBSTR(parm.pc,POS('=',parm.pc)+1))
  end
  when (POS('TBLNAM',parm.pc) > 0) then do
   tblnamParm = STRIP(SUBSTR(parm.pc,POS('=',parm.pc)+1))
  end
  when (POS('TBLENC',parm.pc) > 0) then do
   userTableEnc = STRIP(SUBSTR(parm.pc,POS('=',parm.pc)+1))
  end
  when (POS('(',parm.pc) > 0) then do
   opts = TRANSLATE(STRIP(SUBSTR(parms,POS('(',parms)+1)))
  end
  otherwise nop
 end
 pc = pc+1
end

if filePath = '' then do
 say 'Required program argument - filePath - is missing'
 finalRC = 1
 call Exit finalRC
end

/* Remove quotes, in case the table encoding type is quoted           */
userTableEnc = RemQuotes(userTableEnc)

/* handle if the user defined encoding type is EBCDIC but user
   defined it in a different way                                      */
select
 when userTableEnc = 'IBM-1047' then userTableEnc = ''
 when userTableEnc = 'IBM1047' then userTableEnc = ''
 when userTableEnc = 'US-1047' then userTableEnc = ''
 when userTableEnc = 'US1047' then userTableEnc = ''
 when userTableEnc = '1047' then userTableEnc = ''
 when userTableEnc = 'EBCDIC' then userTableEnc = ''
 otherwise nop
end

/* check run mode                                                     */
runmodeText = 'created'                      /* text for NEW run mode */
select
 when (POS('REPL',opts) > 0 | POS('REPLACE',opts) > 0) &,
       POS('FORCE',opts) = 0 then do
  repl = 'REPLACE'                        /* run mode is just REPLACE */
  force = ''                            /* and FORCE is not in effect */
 end
 when POS('FORCE',opts) > 0 then do
  repl = 'REPLACE'                             /* run mode is REPLACE */
  force = 'FORCE'                                        /* and FORCE */
 end
 otherwise do
  repl = ''                                /* default run mode is NEW */
  force = ''                            /* and FORCE is not in effect */
 end
end

/* Remove quotes, in case the path is quoted                          */
filePath = RemQuotes(filePath)

/* Read json file and put it into a stem ******************************/
address SYSCALL
signal on error name Err_open_file

/* Open the file for only read                                        */
"open" filePath O_RDONLY
fd=retVal

signal on error name Err_read_file
/* Read the file and store its content                                */
json = ''
maximumLength = 9999999      /* maximum JSON length is 9.999.999 char */
"read" fd "json" maximumLength

/* Close the file                                                     */
"close" fd

signal off error

/* Start parsing json input *******************************************/

/* Get Web Enablement Toolkit REXX constants                          */
call JSON_getToolkitConstants
if result <> 0 then do
 call FatalError('** JSON Environment error **')
 call Exit finalRC
 PROC_GLOBALS = 'VERBOSE parserHandle '||HWT_CONSTANTS
end

/* Create a new parser instance                                       */
parserHandle = ''
call JSON_initParser
if result <> 0 then do
 call FatalError('** JSON Parser init failure **')
 call Exit finalRC
end

/* Parse JSON input                                                   */
call JSON_parseJson json
if result <> 0 then do
 call JSON_termParser
 call FatalError('** JSON Parse failure **')
 call Exit finalRC
end

/* Get JSON encoding                                                  */
call JSON_getEncoding
if result <> 0 then do
 call JSON_termParser
 call FatalError('** JSON Parser Get Encoding failure **')
 call Exit finalRC
end

/* Remove quotes, in case the table name is quoted                    */
tblNamParm = RemQuotes(tblNamParm)

/* Convert constant object names to UTF8 if that type was discovered  */
if jsonEnc = HWTJ_ENCODING_UTF8 then do
 if dsnParm = '' then c_dsnTxt = E2u8('dsn')
 if tblNamParm = '' then c_tableTxt = E2u8('table')
 c_numRowsTxt = E2u8('num_rows')
 c_keysTxt = E2u8('keys')
 c_namesTxt = E2u8('names')
 c_dataTxt = E2u8('data')
end
else do
 if dsnParm = '' then c_dsnTxt = 'dsn'
 if tblNamParm = '' then c_tableTxt = 'table'
 c_numRowsTxt = 'num_rows'
 c_keysTxt = 'keys'
 c_namesTxt = 'names'
 c_dataTxt = 'data'
end

/* Get base info from the beggining of the file                       */
 call JSON_getBaseInfo
 if result <> 0 then do
  call JSON_termParser
  call FatalError('** JSON - get base info failure **')
  call Exit finalRC
 end

/* Perform processing keys array                                      */
 call JSON_processKeysArray
 if result <> 0 then do
  call JSON_termParser
  call FatalError('** JSON - process keys array failure **')
  call Exit finalRC
 end

/* Perform processing names array                                     */
 call JSON_processNamesArray
 if result <> 0 then do
  call JSON_termParser
  call FatalError('** JSON - process names array failure **')
  call Exit finalRC
 end

/* Start table related operations *************************************/
datasetAllocated = 0
libraryAllocated = 0
tableOpened = 0
if tblNamParm <> '' then tblNam = tblNamParm

signal on error name Err_alloc

if dsnParm <> '' then dsn = dsnParm
if LEFT(dsn,1) <> "'" then dsn = "'"||dsn||"'"

address TSO
"alloc f(tables) da("dsn") shr reuse"
"alloc f(tabl) da("dsn") shr reuse"
datasetAllocated = 1

address ISPEXEC
"control errors return"
"libdef ISPTLIB library id(tables)"
"libdef ISPTABL library id(tabl)"
libraryAllocated = 1

signal off error
signal on Syntax

/* Check whether table is existing and the structure is the same      */
if repl <> '' then call CheckExistingTable
/* Create table                                                       */
if keys = '' then do
 "TBCREATE" tblNam" NAMES("names") WRITE" repl
end
else do
 "TBCREATE" tblNam" KEYS("keys") NAMES("names") WRITE" repl
end
if RC <> 0 then do
 call Err_create
end
"TBCLOSE" tblNam
if RC <> 0 then call Err_close
"TBOPEN" tblNam "WRITE"
if RC <> 0 then call Err_open
tableOpened = 1
result = 0

/* Continue parsing json input ****************************************/

/* Perform processing data array                                      */
 call JSON_processDataArray
 if result <> 0 then do
  call JSON_termParser
  call FatalError('** JSON - process data array failure **')
  call Exit finalRC
 end

/* Free the parser instance                                           */
 call JSON_termParser
 if result <> 0 then do
  call FatalError('** JSON Parser term failure **')
  call Exit finalRC
 end

/* Write out a process summary                                        */
say 'Table - 'tblNam' - in table library - 'dsn' - has been',
    runmodeText' successfully.'
say numRows '- 'rowsText' been processed with the following keys',
    'and table names:'
say ''
say 'Keys: 'keys
say ''
say 'Table names: 'names
say ''
finalRC = 0

/* exit from the program                                              */
call Exit finalRC


/**********************************************************************/
/* Functions and subroutines                                          */
/**********************************************************************/

/* remove unecessary quotes from the both side of the string **********/
RemQuotes: procedure
 string = ARG(1)
 string = STRIP(string)
 if POS("'", string) = 1 | POS('"', string) = 1 then do
  if POS("'", string) = 1 then do
   string = STRIP(string, "B", "'")
  end
  else do
   string = STRIP(string, "B", '"')
  end
 end
return string

/**********************************************************************/
/* Converts the input string to utf8 using iconv() shell utility.     */
/* Assumes the input string is encoded as IBM-1047 (EBCDIC)           */
/* Returns converted string, or empty string if error                 */
/**********************************************************************/
E2u8: procedure
 parse arg str
 u8Str = ''
 if str <> '' then u8Str = conv(str, "IBM-1047", "UTF-8")
 /* Remove trailing UTF-8 LF appended to stdout                       */
 if u8Str <> '' then u8Str = STRIP(u8Str,'T','0A'x)
return u8Str

/**********************************************************************/
/* Converts the input string to IBM-1047 using iconv() shell utility. */
/* Assumes the input string is UTF-8 encoded                          */
/* Returns converted string, or empty string if error                 */
/**********************************************************************/
U82e: procedure
 parse arg str
 ebcStr = ''
 if str <> '' then ebcStr = conv(str, "UTF-8", "IBM-1047")
 /* During the conversion, an EBCDIC newline (x'15') is appended
   to the input string prior to the conversion. This is converted to
   an UTF-8 <NAK> x'3D', which should be stripped from the output.    */
 if ebcStr <> '' then ebcStr = STRIP(ebcStr,'T','3D'x)
return ebcStr

/**********************************************************************/
/* Converts the input string from the detected encoding type to the   */
/* user defined encoding type using iconv() shell utility.            */
/* Returns converted string, or empty string if error                 */
/**********************************************************************/
e2ud:
 parse arg str
 select
  when str = '' then udStr = str
  when userTableEnc <> '' & jsonEnc = HWTJ_ENCODING_UTF8 then do
   udStr = conv(str, "UTF-8", userTableEnc)
   if udStr <> '' then udStr = STRIP(udStr,'T','3D'x)
  end
  when userTableEnc <> '' & jsonEnc = HWTJ_ENCODING_EBCDIC then do
   udStr = conv(str, "IBM-1047", userTableEnc)
  end
  when userTableEnc = '' & jsonEnc = HWTJ_ENCODING_UTF8 then do
   udStr = U82e(str)
  end
  otherwise udStr = str
 end
return udStr

/**********************************************************************/
/* Converts the input string from the specified source encoding to    */
/* the specified target encoding using iconv() shell utility.         */
/**********************************************************************/
Conv: procedure
 parse arg inStr, srcEnc, tgtEnc
 outStr = ''
 cmdErr. = ''
 cmdIn. = ''
 cmdIn.0 = 1
 cmdIn.1 = inStr
 iconvCmd = 'iconv -f' srcEnc '-t' tgtEnc
 bpxRc = bpxwunix(iconvCmd,'cmdIn.', 'cmdOut.', 'cmdErr.')
 if bpxRc <> 0 then do
  say 'Unable to convert string data from 'srcEnc 'to' tgtEnc
  say 'RC='bpxRc
  call Exit
 end
 do i = 1 to cmdOut.0
  outStr = outStr||cmdOut.i
 end
return outStr

/* Loop through the base info keys ************************************/
JSON_getBaseInfo:
 /* Get dsn from the root object if it's not specified as a parameter */
 if dsnParm = '' then do
  dsn = JSON_findValue(0, c_dsnTxt, HWTJ_STRING_TYPE)
  if dsn = '' then do
   say 'The DSN parameter is neither in the program parameters nor in',
       'the JSON root object.'
   finalRC = 1
   call Exit finalRC
  end
  if jsonEnc = HWTJ_ENCODING_UTF8 then dsn = U82e(dsn)
 end
 /* Get table name from the root object if it's not specified as a
    parameter                                                         */
 if tblNamParm = '' then do
  tblNam = JSON_findValue(0, c_tableTxt, HWTJ_STRING_TYPE)
  if tblNam = '' then do
   say 'The TBLNAME parameter is neither in the program parameters',
       'nor in the JSON root object.'
   finalRC = 1
   call Exit finalRC
  end
  if jsonEnc = HWTJ_ENCODING_UTF8 then tblNam = U82e(tblNam)
 end
 /* Get num rows from the root object                                 */
 numRows = JSON_findValue(0, c_numRowsTxt, HWTJ_NUMBER_TYPE)
 if jsonEnc = HWTJ_ENCODING_UTF8 then numRows = U82e(numRows)
 if numRows = '' | numRows = 0 then numRows = '?'
 rowsText = 'rows have'                     /* text for multiple rows */
 if numRows = 1 then rowsText = 'row has'    /* text for only one row */
return 0

/* Loop through the keys array ****************************************/
JSON_processKeysArray:
 /* Get the keys array from the root object                           */
 keysArray = JSON_findValue(0, c_keysTxt, HWTJ_ARRAY_TYPE)
 if result <> 0 then do
  return FatalError('** Unable to locate keys array **')
 end
 /* Determine the number of data represented in the array             */
 numData = JSON_getArrayDim(keysArray)
 if numData < 0 then do
  return FatalError('** Unable to retrieve number of keys array',
   'entries **')
 end
 tblKeys.0 = numData
 keys = ''
 if tblKeys.0 > 0 then do
  /* Traverse the keys array                                          */
  do i = 1 to tblKeys.0
   nextEntryHandle = JSON_getArrayEntry(keysArray,i-1)
   tblKeys.i = JSON_getValue(nextEntryHandle, HWTJ_STRING_TYPE)
   if jsonEnc = HWTJ_ENCODING_UTF8 then tblKeys.i = U82e(tblKeys.i)
   keys = keys||' '||tblKeys.i
  end
 end
return 0

/* Loop through the names array ***************************************/
JSON_processNamesArray:
 /* Get the names array from the root object                          */
 namesArray = JSON_findValue(0, c_namesTxt, HWTJ_ARRAY_TYPE)
 if result <> 0 then do
  return FatalError('** Unable to locate names array **')
 end
 /* Determine the number of data represented in the array             */
 numData = JSON_getArrayDim(namesArray)
 if numData <= 0 then do
  return FatalError('** Unable to retrieve number of names array',
   'entries **')
 end
 /* Traverse the names array                                          */
 tblNames.0 = numData
 names = ''
 do i = 1 to numData
  nextEntryHandle = JSON_getArrayEntry(namesArray,i-1)
  tblNames.i = JSON_getValue(nextEntryHandle, HWTJ_STRING_TYPE)
  if jsonEnc = HWTJ_ENCODING_UTF8 then tblNames.i = U82e(tblNames.i)
  names = names||' '||tblNames.i
 end
return 0

/* Check existing table structure if it really exists *****************/
CheckExistingTable:
 "TBOPEN" tblNam "NOWRITE"
 select
  when RC = 0 then do
   tableOpened = 1
   /* Sort the keys to be imported                                    */
   if tblKeys.0 > 0 then keys = SortElementsOfList(keys)
   names = SortElementsOfList(names) /* sort the names to be imported */
   /* Query table to get keys and names of the existing table         */
   "TBQUERY" tblNam "KEYS("qKeys") NAMES("qNames")"
   if RC > 0 then call Err_query
   qKeys = STRIP(qKeys,'L','(')
   qKeys = STRIP(qKeys,'T',')')
   qNames = STRIP(qNames, 'L', '(')
   qNames = STRIP(qNames, 'T', ')')
   qKeys = SortElementsOfList(qKeys)        /* sort the querried keys */
   qNames = SortElementsOfList(qNames)     /* sort the querried names */
   /* Check whether the existing table's keys and names match with
      keys and names of the new table to be imported                  */
   select
    when (keys = qKeys) & (names = qNames) then do
     say 'Info: The structure of the new table to be imported is the',
         'same as the existing table - so program is going to replace',
         'it as option REPLACE is in effect.'
     say ''
     runmodeText = 'replaced'            /* text for REPLACE run mode */
    end
    when ((keys <> qKeys) | (names <> qNames)) & force = '' then do
     say 'Error: The structure of the new table to be imported is',
         'different than the existing table - so please make sure',
         'you are replacing the right table.'
     say 'If you are sure, re-run the program with option FORCE.'
     say ''
     finalRC = 8
     call Exit finalRC
    end
    when ((keys <> qKeys) | (names <> qNames)) & force = 'FORCE',
     then do
     say 'Warning: The structure of the new table to be imported is',
         'different than the existing table - but you are running the',
         'program with option FORCE, so table will be replaced anyway.'
     say ''
     runmodeText = 'replaced'            /* text for REPLACE run mode */
    end
    otherwise nop
   end
   "TBCLOSE" tblNam
   if RC <> 0 then call Err_close
  end
  when RC = 8 then return  /* table doesn't exist -> no need to check */
  when RC > 8 then call Err_open
 end
return

/* Sort the elements of a list (separeted by blank)********************/
SortElementsOfList: procedure
 list = ARG(1)
 do imx = 1 to WORDS(list)-1
  do im = 1 to WORDS(list)
   w1 = WORD(list,im)
   w2 = WORD(list,im+1)
   if w1 > w2 then do
    if im > 1 then
     lm = SUBWORD(list,1,im-1)
    else do
     lm = ''
    end
    rm = SUBWORD(list,im+2)
    /* Just to avoid the unnecessary blank before the last element    */
    if w2 = '' then do
     list = lm w1 rm
    end
    else do
     list = lm w2 w1 rm
    end
   end
  end
 end
 list = STRIP(list)
return list

/* Loop through the data array ****************************************/
JSON_processDataArray:
 /* Get the data array from the root object                           */
 dataArray = JSON_findValue(0, c_dataTxt, HWTJ_ARRAY_TYPE)
 if result <> 0 then do
  return FatalError('** Unable to locate data array **')
 end
 /* Determine the number of data represented in the array             */
 numData = JSON_getArrayDim(dataArray)
 if numData <= 0 then do
  return FatalError('** Unable to retrieve number of data array',
   'entries **')
 end
 if numRows = '?' then numRows = numData
 /* Traverse the data array                                           */
 do i = 1 to numData
  nextEntryHandle = JSON_getArrayEntry(dataArray,i-1)
  call StoreDataInformation nextEntryHandle
  if result <> 0 then do
   return FatalError('** Error while processing data ('||i-1||') **')
  end
 end
return 0

/**********************************************************************/
/* Retrieves values from the designated data entry and store them     */
/* into the opened ISPF table                                         */
/**********************************************************************/
StoreDataInformation:
 entryHandle = ARG(1)
 if tblKeys.0 > 0 then do
  /* handle table keys first                                          */
  do keyc=1 to tblKeys.0
   if jsonEnc = HWTJ_ENCODING_UTF8 then do
    interpret tblKeys.keyc' = JSON_findValue(',
     'entryHandle,"'E2u8(tblKeys.keyc)'",HWTJ_STRING_TYPE)'
   end
   else do
    interpret tblKeys.keyc' = JSON_findValue(',
     'entryHandle,"'tblKeys.keyc'",HWTJ_STRING_TYPE)'
    /* interpret 'say tblKeys.keyc ": 'VALUE(tblKeys.keyc)'"' */
   end
   interpret tblKeys.keyc' = e2ud('tblKeys.keyc')'
  end
 end
 /* handle table names (column names)                                 */
 do namesc=1 to tblNames.0
  if jsonEnc = HWTJ_ENCODING_UTF8 then do
   interpret tblNames.namesc' = JSON_findValue(',
    'entryHandle,"'E2u8(tblNames.namesc)'",HWTJ_STRING_TYPE)'
  end
  else do
   interpret tblNames.namesc' = JSON_findValue(',
   'entryHandle,"'tblNames.namesc'",HWTJ_STRING_TYPE)'
   /* interpret 'say tblNames.namesc ": 'VALUE(tblNames.namesc)'"' */
  end
  interpret tblNames.namesc' = e2ud('tblNames.namesc')'
 end
 signal on error name Err_add_rows
 address ISPEXEC
 "TBADD "tblNam "SAVE("keys names")"
return 0

/**********************************************************************/
/* Return a handle to the designated entry of the array designated by */
/* the input handle obtained via the HWTJGAEN toolkit api.            */
/**********************************************************************/
JSON_getArrayEntry:
 arrayHandle = ARG(1)
 whichEntry = ARG(2)
 result = ''
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjgaen ",
                 "returnCode ",
                 "parserHandle ",
                 "arrayHandle ",
                 "whichEntry ",
                 "handleOut ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjgaen', RexxRC, returnCode, diagArea.
  say '** hwtjgaen failure **'
 end
 else do
  result = handleOut
 end
return result

/**********************************************************************/
/* Return the number of entries in the array designated by the input  */
/* handle, obtained via the HWTJGNUE toolkit api.                     */
/**********************************************************************/
JSON_getArrayDim:
 arrayHandle = ARG(1)
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjgnue ",
                 "returnCode ",
                 "parserHandle ",
                 "arrayHandle ",
                 "dimOut ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjgnue', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjgnue failure **')
 end
 arrayDim = STRIP(dimOut,'L',0)
 if arrayDim == '' then return 0
return arrayDim

/**********************************************************************/
/* Return the value portion of the designated Json object according   */
/* to its type                                                        */
/**********************************************************************/
JSON_getValue:
 entryHandle = ARG(1)
 valueType = ARG(2)
 /* Get the value for a String or Number type                         */
 if valueType == HWTJ_STRING_TYPE |,
    valueType == HWTJ_NUMBER_TYPE then do
  returnCode = -1
  diagArea. = ''
  address HWTJSON "hwtjgval ",
                  "returnCode ",
                  "parserHandle ",
                  "entryHandle ",
                  "valueOut ",
                  "diagArea."
  RexxRC = RC
  if JSON_isError(RexxRC,returnCode) then do
   call JSON_surfaceDiag 'hwtjgval', RexxRC, returnCode, diagArea.
   say '** hwtjgval failure **'
   valueOut = ''
  end
  return valueOut
 end
 /* Get the value for a Boolean type                                  */
 if valueType == HWTJ_BOOLEAN_TYPE then do
  returnCode = -1
  diagArea. = ''
  address HWTJSON "hwtjgbov ",
                  "returnCode ",
                  "parserHandle ",
                  "entryHandle ",
                  "valueOut ",
                  "diagArea."
  RexxRC = RC
  if JSON_isError(RexxRC,returnCode) then do
   call JSON_surfaceDiag 'hwtjgbov', RexxRC, returnCode, diagArea.
   say '** hwtjgbov failure **'
   valueOut = ''
  end
  return valueOut
 end
 /* For NULL type                                                     */
 if valueType == HWTJ_NULL_TYPE then do
  valueOut = '*null*'
  say 'Returning arbitrary '||valueOut||' for null type'
  return valueOut
 end
 /*********************************************************************/
 /* To reach this point, valueType must be a non-primitive type       */
 /* (i.e., either HWTJ_ARRAY_TYPE or HWTJ_OBJECT_TYPE), and we        */
 /* simply echo back the input handle as our return value             */
 /*********************************************************************/
return entryHandle

/**********************************************************************/
/* Return the value associated with the input name from the           */
/* the designated Json object                                         */
/**********************************************************************/
JSON_findValue:
 objectToSearch = ARG(1)
 searchName = ARG(2)
 expectedType = ARG(3)
 /* Search the specified object for the specified name                */
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjsrch ",
                 "returnCode ",
                 "parserHandle ",
                 "HWTJ_SEARCHTYPE_OBJECT ",
                 "searchName ",
                 "objectToSearch ",
                 "0 ",
                 "searchResult ",
                 "diagArea."
 RexxRC = RC
 /* Differentiate a not found condition from an error                 */
 if JSON_isNotFound(RexxRC,returnCode) then do
  return '(not found)'
 end
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjsrch', RexxRC, returnCode, diagArea.
  say '** hwtjsrch failure **'
  return ''
 end
 /* Process the search result, according to type.  We should first
    verify the type of the search result                              */
 resultType = JSON_getType(searchResult)
 if resultType <> expectedType then do
  say '** Type mismatch ('||resultType||','||expectedType||') **'
  return ''
 end
 /* If the expected type is not a simple value, then the search result
    is itself a handle to a nested object or array, and return it     */
 if expectedType == HWTJ_OBJECT_TYPE |,
    expectedType == HWTJ_ARRAY_TYPE then do
  return searchResult
 end
 /* Return the located string or number, as appropriate               */
 if expectedType == HWTJ_STRING_TYPE |,
    expectedType == HWTJ_NUMBER_TYPE then do
  returnCode = -1
  diagArea. = ''
  address HWTJSON "hwtjgval ",
                  "returnCode ",
                  "parserHandle ",
                  "searchResult ",
                  "result ",
                  "diagArea."
  RexxRC = RC
  if JSON_isError(RexxRC,returnCode) then do
   call JSON_surfaceDiag 'hwtjgval', RexxRC, returnCode, diagArea.
   say '** hwtjgval failure **'
   return ''
  end
  return result
 end
 /* Return the located boolean value, as appropriate                  */
 if expectedType == HWTJ_BOOLEAN_TYPE then do
  returnCode = -1
  diagArea. = ''
  address HWTJSON "hwtjgbov ",
                  "returnCode ",
                  "parserHandle ",
                  "searchResult ",
                  "result ",
                  "diagArea."
  RexxRC = RC
  if JSON_isError(RexxRC,returnCode) then do
   call JSON_surfaceDiag 'hwtjgbov', RexxRC, returnCode, diagArea.
   say '** hwtjgbov failure **'
   return ''
  end
  return result
 end
 /* This return should not occur, in practice                         */
 say '** No return value found **'
return ''

/**********************************************************************/
/* Determine the Json type of the designated search result via the    */
/* HWTJGJST toolkit api.                                              */
/**********************************************************************/
JSON_getType:
 searchResult = ARG(1)
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjgjst ",
                 "returnCode ",
                 "parserHandle ",
                 "searchResult ",
                 "resultTypeName ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjgjst', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjgjst failure **')
 end
 else do
  /* Convert the returned type name into its equivalent constant, and
     return that more convenient value.                               */
  type = STRIP(resultTypeName)
  if type == 'HWTJ_STRING_TYPE' then return HWTJ_STRING_TYPE
  if type == 'HWTJ_NUMBER_TYPE' then return HWTJ_NUMBER_TYPE
  if type == 'HWTJ_BOOLEAN_TYPE' then return HWTJ_BOOLEAN_TYPE
  if type == 'HWTJ_ARRAY_TYPE' then return HWTJ_ARRAY_TYPE
  if type == 'HWTJ_OBJECT_TYPE' then return HWTJ_OBJECT_TYPE
  if type == 'HWTJ_NULL_TYPE' then return HWTJ_NULL_TYPE
 end
 /* This return should not occur, in practice                         */
return FatalError('Unsupported Type ('||type||') from hwtjgjst')

/**********************************************************************/
/* Access constants used by the toolkit (for return codes, etc), via  */
/* the HWTCONST toolkit api.                                          */
/**********************************************************************/
JSON_getToolkitConstants:
 call hwtcalls "on"
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtconst ",
                 "returnCode ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then
  do
  call JSON_surfaceDiag 'hwtconst', RexxRC, returnCode, diagArea.
  return FatalError('** hwtconst (json) failure **')
 end
return 0

/* Create a Json parser instance via the HWTJINIT toolkit api *********/
JSON_initParser:
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjinit ",
                 "returnCode ",
                 "handleOut ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjinit', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjinit failure **')
 end
 /* Set the all-important global                                      */
 parserHandle = handleOut
return 0

/* Parse the input text body via call to the HWTJPARS toolkit api *****/
JSON_parseJson:
 jsonTextBody = ARG(1)
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjpars ",
                 "returnCode ",
                 "parserHandle ",
                 "jsonTextBody ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjpars', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjpars failure **')
 end
return 0

/* Get JSON encoding via the HWTJGENC toolkit api *********************/
JSON_getEncoding:
 jsonEnc = -1
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjgenc ",
                 "returnCode ",
                 "parserHandle ",
                 "jsonEnc ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjgenc', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjgenc failure **')
 end
return 0

/**********************************************************************/
/* Cleans up parser resources and invalidates the parser instance     */
/* handle, via call to the HWTJTERM toolkit api.                      */
/**********************************************************************/
JSON_termParser:
 returnCode = -1
 diagArea. = ''
 address HWTJSON "hwtjterm ",
                 "returnCode ",
                 "parserHandle ",
                 "diagArea."
 RexxRC = RC
 if JSON_isError(RexxRC,returnCode) then do
  call JSON_surfaceDiag 'hwtjterm', RexxRC, returnCode, diagArea.
  return FatalError('** hwtjterm failure **')
 end
return 0


/**********************************************************************/
/* Error handlers                                                     */
/**********************************************************************/

/* Fatal error ********************************************************/
FatalError:
 errorMsg = ARG(1)
 say errorMsg 'in line' SIGL
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = -1
return -1

/* Check the input processing codes 1 *********************************/
JSON_isNotFound:
 RexxRC = ARG(1)
 if RexxRC <> 0 then return 0
 ToolkitRC = STRIP(ARG(2),'L',0)
 if ToolkitRC == HWTJ_JSRCH_SRCHSTR_NOT_FOUND then return 1
return 0

/* Check the input processing codes 2 *********************************/
JSON_isError:
 RexxRC = ARG(1)
 if RexxRC <> 0 then return 1
 ToolkitRC = STRIP(ARG(2),'L',0)
 if ToolkitRC == '' then return 0
 if ToolkitRC <= HWTJ_WARNING then return 0
return 1

/* Surface input error information ************************************/
JSON_surfaceDiag: procedure expose diagArea. finalRC SIGL
 who = ARG(1)
 RexxRC = ARG(2)
 ToolkitRC = ARG(3)
 say
 say '*ERROR* ('||who||') at time: '||Time() 'in line:' SIGL
 say 'Source line: '||SOURCELINE(SIGL)
 say 'Rexx RC: '||RexxRC||', Toolkit returnCode: '||ToolkitRC
 if who = 'hwtjpars' & ToolkitRC = 265 then do
  say 'This is a syntax or encoding error. Please make sure',
      'JSON text is syntactically correct and it is in EBCDIC',
      'encoding (codepage 1047) or in UTF-8.'
 end
 if RexxRC == 0 then do
  say 'diagArea.ReasonCode: '||diagArea.HWTJ_ReasonCode
  say 'diagArea.ReasonDesc: '||diagArea.HWTJ_ReasonDesc
 end
 finalRC = ToolkitRC
return

/* Error handler for allocations **************************************/
Err_alloc:
 say 'ERROR in line' SIGL
 say 'Allocating 'dsn', RC='RC
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = RC
 call Exit finalRC
return

/* File open error information ****************************************/
Err_open_file:
 if retVal = -1 then do
  say 'ERROR in line' SIGL
  say "Input file >"filePath"< not opened, error codes" errno errnojr
 say 'Source line: '||SOURCELINE(SIGL)
  finalRC = -1
  call Exit finalRC
 end
return

/* File read error information ****************************************/
Err_read_file:
 if retVal = -1 then do
  say 'ERROR in line' SIGL
  say "Input file >"filePath"< unable to read, error codes" errno,
      errnojr
 say 'Source line: '||SOURCELINE(SIGL)
  finalRC = -1
  call Exit finalRC
 end
return

/* Table create error information *************************************/
Err_create:
 select
  when RC = 4 then return           /* table replaced - that's normal */
  when RC = 8 then do
   say 'ERROR in line' SIGL
   say 'Service TBCREATE 'tblNam' failed. Because table already',
       'exists and REPLACE option was not specified within the',
       'invocation parms'
   say ''
   say 'Source line: '||SOURCELINE(SIGL)
   finalRC = RC
   call Exit finalRC
  end
  otherwise do
   say 'ERROR in line' SIGL
   say 'Service TBCREATE 'tblNam' failed. RC('RC')'
   say 'Source line: '||SOURCELINE(SIGL)
   finalRC = RC
   call Exit finalRC
  end
 end
return

/* Table open error information ***************************************/
Err_open:
 say 'ERROR in line' SIGL
 say 'Service TBOPEN 'tblNam' failed. RC('RC')'
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = RC
 call Exit finalRC
return

/* Table query error information **************************************/
Err_query:
 say 'ERROR in line' SIGL
 say 'Service TBQUERY 'tblNam' failed. RC('RC')'
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = RC
 call Exit finalRC
return

/* Table add row error information ************************************/
Err_add_rows:
 say 'ERROR in line' SIGL
 say 'Service TBADD 'tblNam' failed. RC('RC')'
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = RC
 call Exit finalRC
return

/* Table close error information **************************************/
Err_close:
 say 'ERROR in line' SIGL
 say 'Service TBCLOSE 'tblNam' failed. RC('RC')'
 say 'Source line: '||SOURCELINE(SIGL)
 finalRC = RC
 call Exit finalRC
return

/* Syntax error information *******************************************/
Syntax:
 address TSO
 say 'REXX error' RC 'in line' SIGL':' 'ERRORTEXT'(RC)
 say 'Source line: '||SOURCELINE(SIGL)
 call Exit finalRC
return


/**********************************************************************/
/* exit from the program                                              */
/**********************************************************************/
Exit:
 finalRC = ARG(1)
/* Close tables and data sets *****************************************/
 address ISPEXEC
 "control errors return"
 if tableOpened = 1 then do
  "TBCLOSE" tblNam
  if RC > 0 then do
   say 'ERROR in line' SIGL
   say 'Service TBCLOSE 'tblNam' failed. RC('RC')'
  end
 end

/* clear the LIBDEF                                                   */
 if libraryAllocated = 1 then do
  "libdef isptabl"
  "libdef isptlib"
 end

/* Free opened data set(s)                                            */
 address TSO
 if datasetAllocated = 1 then do
  "free f(tables)"
  "free f(tabl)"
 end
exit finalRC
