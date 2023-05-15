# ISPF-Importer
This project - similarly to [ISPF-Exporter](../ISPF-Exporter) - aims to create tooling to work with automation policies managed by IBM Z System Automation. Automation policies, or *policies* in short, are kept in a set of ISPF-tables that are stored in a partitioned data set (PDS). Unlike other popular data formats used today, like XML or JSON, ISPF-tables cannot be used in their raw format. The tables only reside on z/OS and they can only be processed using ISPF-services. Table creation or modification for large amounts of data using even IBM Z System Automation Customization Dialog or ISPF Table Utility (3.16) is slow and complicated in most cases.

So, a tool is needed that makes it easy for developers and admins to create or overwrite ISPF tables based on an input file using a popular data format. That format should be widely used in order to enable processing of the data on any platform of choice. Hence, the task addressed by this project is to import data into ISPF tables from the modern JSON data format. The REXX-script `json2i.rex` takes care of this task.

Because the data to be imported is in JSON format, this project opens ISPF data to modern data science world. It can help for example migration specialists to load pre-processed, structured data into IBM Z System Automation Policy Database (e.g. sort/update/merge customer's automation data using modern programming languages like Python). It can be even used for other products as many z/OS based tools/applications use ISPF table service to store their data in tables.

Note: This version of REXX-script `json2i.rex` is created for importing SA timer definitions. For other SA elements code may need to be extended.

## JSON-format
The data to be imported must be structured with the following schema in the JSON-file (same structure as the output of [ISPF-Exporter](../ISPF-Exporter)):
```
{
    "dsn": string,
    "table": string,
    "num_rows": number,
    "keys": string-array,
    "names": string-array,
    "data": object-array
}
```
The keys should contain the following information:
- **dsn**: Name of the fully qualified partitioned data set (PDS) where the table needs to be loaded - if value is empty (`"dsn": ""`), must be given to REXX-script `json2i.rex` as parameter DSN.
- **table**: Name of the output ISPF table - if value is empty (`"table": ""`), must be given to REXX-script `json2i.rex` as parameter TBLNAM.
- **num_rows**: Number of objects in `"data"` array - the REXX-script `json2i.rex` only uses this number in an informal message at the end of the execution, so it is not significant.
- **keys**: List of the names that are to be used as keys for accessing the table - if list is empty (`"keys": []`), only non-key names will be added.
- **names**: List of the non-key names to be stored in each row of the table.
- **data**: List of the contents of the rows as objects.

**Example**
```
{
    "dsn": "'USER.TABLE.LIB'",
    "table": "CMDTABLE",
    "num_rows": 2,
    "keys": [
        "ID",
        "NAME"
    ],
    "names": [
        "CMD",
        "COMMENT"
    ],
    "data": [
        {
            "ID": "01",
            "NAME": "CMD01",
            "CMD": "MVS d t",
            "COMMENT": "Display time information"
        },
        {
            "ID": "02",
            "NAME": "CMD02",
            "CMD": "MVS d iplinfo",
            "COMMENT": "Display IPL information"
        }
    ]
}
```

## Using the REXX-script
Copy the REXX-script in folder `./rexx-src` to your TSO and store it in a data set in the SYSPROC or SYSEXEC concatenation. You can use any file transfer utility such as FTP for this.

**System requirements**

REXX-script `json2i.rex` has the following requirements:
- **ISPF environment** as script uses ISPF table service to write JSON data into ISPF table
- **z/OS JSON parser** as script uses HWTJ* services to parse JSON input file (z/OS JSON parser is part of z/OS initialization during IPL time from z/OS 2.2)

### Import data into an ISPF table
REXX-script `json2i.rex` has the following syntax:
```
json2i FILEPATH=input-file-path DSN=table-library-pds TBLNAM=table-name TBLENC=table-encoding-type '(' options
```

The parameters have the following meaning:
- **input-file-path**: The case-sensitive path of an existing UNIX System Services file where the input JSON is stored - **mandatory**. JSON file must be encoded in EBCDIC (IBM-1047) or in UTF-8. For example: FILEPATH=/u/user/test.json
- **table-library-pds**: Name of the fully qualified PDS(E) where the table needs to be loaded - **optional**. If not specified, program tries to read it from the JSON root object. For example: DSN='USER.TABLE.LIB'
- **table-name**: Maximum 8-char long output ISPF table name - **optional**. If not specified, program tries to read it from the JSON root object. For example: TBLNAM=AAATABLE
- **table-encoding-type**: Encoding type of the output ISPF table - **optional**. If not specified, IBM-1047 is the default. For example: TBLENC=IBM-500
- **options**: Script options - currently only the REPLACE and FORCE parameters are supported - **optional**. It must begin with an opening parenthesis. For example: (REPL FORCE
  - **REPLACE or REPL**: ISPF table will be replaced if there is already a table with the same name and the same structure (keys and column names) as the table to be imported
  - **FORCE**: ISPF table will be replaced regardless of whether the structure is the same as the existing one or not

**Examples**

Use the following command to import for instance SA timer definitions into a table `AOFTTMX` within table library `SA43.TEST.PDB` using input JSON file `/u/ibmuser/SA_timers.json`:
```
json2i FILEPATH=/u/ibmuser/SA_timers.json DSN=SA43.TEST.PDB TBLNAM=AOFTTMX
```
or the same but with the table encoding type `IBM-500` and using option `REPL` (if table already exists in the table library) and option `FORCE` (if the structure of the table to be imported is different than the existing table):
```
json2i FILEPATH=/u/ibmuser/SA_timers.json DSN=SA43.TEST.PDB TBLNAM=AOFTTMX TBLENC=IBM-500 (REPL FORCE
```

**Invoke script using a batch job**

It is also possible to invoke the REXX-script `json2i.rex` using a JCL job, here is an example:
```
[JOBCARD]
//********************************************************************/
// EXPORT SYMLIST=(FILEPATH,DSN,TBLNAM,TBLENC,OPTS,SYSPROC)
//********************************************************************/
// SET FILEPATH='/u/user/test.json'              /* Input JSON file  */
// SET      DSN='USER.TABLE.LIB'                 /* Output dataset   */
// SET   TBLNAM='AAATABLE'                       /* Table name       */
// SET   TBLENC='IBM-1047'                       /* Table encoding   */
// SET     OPTS='(FORCE'                         /* Options          */
// SET  SYSPROC=SCM.JSON2I.REXXLIB               /* Program LIB      */
//********************************************************************/
//INVJ2I   EXEC PGM=IKJEFT01
//ISPMLIB  DD DSN=SYS1.ISPF.SISPMENU,DISP=SHR  /* ISPF MESSAGE Lib.  */
//ISPSLIB  DD DSN=SYS1.ISPF.SISPSLIB,DISP=SHR  /* ISPF SKELETON Lib. */
//ISPPLIB  DD DSN=SYS1.ISPF.SISPPENU,DISP=SHR  /* ISPF PANEL Library */
//ISPTLIB  DD DSN=SYS1.ISPF.SISPTENU,DISP=SHR  /* ISPF TABLE Library */
//SYSPROC  DD DISP=SHR,DSN=&SYSPROC
//ISPTABL  DD UNIT=SYSDA,DISP=(NEW,PASS),SPACE=(CYL,(1,1,5)),
//            DCB=(LRECL=80,BLKSIZE=19040,DSORG=PO,RECFM=FB),
//            DSN=&&TABLESP
//ISPPROF  DD UNIT=SYSDA,DISP=(NEW,PASS),SPACE=(CYL,(1,1,5)),
//            DCB=(LRECL=80,BLKSIZE=19040,DSORG=PO,RECFM=FB),
//            DSN=&&TABLESP
//ISPLOG   DD SYSOUT=*,
//            DCB=(LRECL=120,BLKSIZE=2400,DSORG=PS,RECFM=FB)
//SYSTSPRT DD SYSOUT=*
//SYSPRINT DD SYSOUT=*
//SYSTSIN  DD *,SYMBOLS=JCLONLY
 ISPSTART CMD(%JSON2I +
              FILEPATH=&FILEPATH +
              DSN=&DSN TBLNAM=&TBLNAM +
              TBLENC=&TBLENC &OPTS)
//
```
Note: If only the option `FORCE` is specified, it is the same as both `REPLACE` and `FORCE` would be specified.

**Errors**

If errors occur, the reason is shown in form of a TSO/ISPF message, z/OS JSON parser message (return or abend codes from HWTJ* services) or in form of a message issued by the tool itself. For example, the following message shows a situation where the input directory doesn't exist. 
```
ERROR in line 197
Input file >/u/ibmuser/SA_timers.json< unable to read, error codes 81 594003D
Source line: "read" fd "json" maximumLength
```
The first error code (`81`) is the hexadecimal return code (errno). The second part (`594003D`) is the hexadecimal reason code (errnojrs) of which the last 4 digits are of most interest. Above message indicates errno ENOENT (No such file, directory, or IPC member exists.) and errnojr JRDirNotFound.

Or another example, the following message shows a situation where the structure of the table to be imported is different than the existing table but option FORCE was not defined.
```
Error: The structure of the new table to be imported is different than the existing table - so please make sure you are replacing the right table.
If you are sure, re-run the program with option FORCE.
```

# Useful references
For information regarding ISPF-service usage, refer to the following publication:

- _z/OS 2.5 ISPF Services Guide_ ([link](https://www.ibm.com/docs/en/zos/2.5.0?topic=ispf-zos-services-guide))

For information about the z/OS JSON parser usage, refer to the following publication:

- _z/OS 2.5 MVS Programming: Callable Services for High-Level Languages_ ([link](https://www.ibm.com/docs/en/zos/2.5.0?topic=toolkit-zos-json-parser))

For information about the specific meaning of error codes, refer to the publication below.

- _z/OS 2.5 UNIX System Services Messages and Codes_ ([link](https://www.ibm.com/docs/en/zos/2.5.0?topic=services-zos-unix-system-messages-codes))