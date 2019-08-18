/**************************************************************************
Iterate through all fragmented indexes of the current database 
and reorganize/rebuild them.

The script will only be runnable on SQL Server > 2005. All databases with a 
compatibility_level < 90 (SQL 2005) will be skipped.

All index rebuilds will be executed as an offline operation, so this script should
be scheduled to run offtime.

Please check and modify the current scanlevel in the 2 dynamic SQL statements 
depending on target database (currently set to "LIMITED"


Scanning Modes

The mode in which the function is executed determines the level of scanning performed to obtain the statistical data that is used by the function. 
mode is specified as LIMITED, SAMPLED, or DETAILED. The function traverses the page chains for the allocation units that make up the specified 
partitions of the table or index. sys.dm_db_index_physical_stats requires only an Intent-Shared (IS) table lock, regardless of the mode that it runs in. 
For more information about locking, see Lock Modes.
The LIMITED mode is the fastest mode and scans the smallest number of pages. For an index, only the parent-level pages of the B-tree (that is, the pages 
above the leaf level) are scanned. For a heap, only the associated PFS and IAM pages are examined; the data pages of the heap are not scanned. In 
SQL Server 2005, all pages of a heap are scanned in LIMITED mode.
With LIMITED mode, compressed_page_count is NULL because the Database Engine only scans non-leaf pages of the B-tree and the IAM and PFS pages of the heap. 
Use SAMPLED mode to get an estimated value for compressed_page_count, and use DETAILED mode to get the actual value for compressed_page_count..The SAMPLED mode returns statistics based on a 1 percent sample of all the pages in the index or heap. If the index or heap has fewer than 10,000 pages, DETAILED mode is used instead of SAMPLED.
The DETAILED mode scans all pages and returns all statistics.
The modes are progressively slower from LIMITED to DETAILED, because more work is performed in each mode. To quickly gauge the size or fragmentation level of a table or index, use the LIMITED mode. It is the fastest and will not return a row for each nonleaf level in the IN_ROW_DATA allocation unit of the index.

**************************************************************************/
SET NOCOUNT ON
GO
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
GO

DECLARE @tabname SYSNAME, @schema SYSNAME, @idxname SYSNAME, @idxtype VARCHAR(50), @query VARCHAR(2000)

DECLARE @avgfrag FLOAT, @pagecount_threshold INT, @fillfactor CHAR(2), @logsize INT, @logsize_threshold INT
DECLARE @exitcode int, @sqlerrorcode int
DECLARE @fraglevel INT	-- fragmentation threshold for indexes in %
-- set minimum index fragmentation threshold as filter argument here, @fraglevel must be < 30. 
-- All indexes with a fragmentation from @fraglevel to 30 will be reorganized. Indexes with a higher 
-- fragmentation level will be rebuilt. E.g. an index Idx_1 fragmented with 25% would be reorganized,
-- an index Idx_2 fragmented with 45% would be rebuilt. 
SET @fraglevel = 15
-- http://technet.microsoft.com/en-us/library/cc966523.aspx
SET @pagecount_threshold = 10000 -- process only indexes with a given pagecount beyond given threshold (see link above)
SET @fillfactor = '80' -- fill factor for index rebuild in %
------------------------------------------------------------------------------------------------------------------
DECLARE @debugmode BIT
SET @debugmode = 0  -- set @debugmode to 1 to print out sql statements without executing
-- recheck for valid lower bound fraglevel
IF @fraglevel >= 30 SET @fraglevel = 29

-- cat view 'sys.dm_db_index_physical_stats' only available in SQL 2005 databases and higher versions
-- check only SQL 2005 and higher databases that are online
IF EXISTS (SELECT database_id FROM sys.databases WHERE database_id = DB_ID()
													AND [state] = 0 
													AND compatibility_level >= 90)
BEGIN

	/*** Zunächst werden die stark fragmentierten Indizes neu aufgebaut. ***/
	SET @query =	'DECLARE IdxCursor CURSOR GLOBAL READ_ONLY ' + 
					'FOR SELECT DISTINCT o.name tabname, s.name [schema], i.name idxname, a.avg_fragmentation_in_percent, a.index_type_desc ' + 
						'FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , ''LIMITED'') a ' + 
						'INNER JOIN sys.objects o ON a.object_id = o.object_id ' + 
						'INNER JOIN sys.schemas s ON o.schema_id = s.schema_id ' + 
						'INNER JOIN sys.indexes i ON o.object_id = i.object_id AND a.index_id = i.index_id ' + 
						'WHERE avg_fragmentation_in_percent > 30 ' +
						'AND a.page_count > ' + CONVERT(VARCHAR, @pagecount_threshold) + ' ' +
						'AND index_type_desc <> ''HEAP'' ' + 
						'ORDER BY a.index_type_desc, a.avg_fragmentation_in_percent desc; '
	EXEC (@query)

	PRINT CHAR(13) + CHAR(10) + '=======================================================================' + CHAR(13) + CHAR(10) + 
			'Searching for indexes with a fragmentation > 30 % for rebuild...' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
	OPEN IdxCursor
	FETCH NEXT FROM IdxCursor INTO @tabname, @schema, @idxname, @avgfrag, @idxtype
	WHILE ( @@fetch_status <> -1 )
	BEGIN
		PRINT 'Fragmentation of ' + @idxtype + ' ' + @idxname + ' in ' + @schema + '.' + @tabname + ': ' + 
			  CONVERT(VARCHAR, @avgfrag) + '. Will be rebuilt (offline).'
		PRINT 'ALTER INDEX ' + @idxname + ' ON ' + @schema + '.' + @tabname + ' REBUILD WITH (FILLFACTOR = ' + @fillfactor + ');' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
		IF @debugmode = 0 
		BEGIN
			EXEC ('ALTER INDEX ' + @idxname + ' ON ' + @schema + '.' + @tabname + ' REBUILD WITH (FILLFACTOR = ' + @fillfactor + ');')
		END

		FETCH NEXT FROM IdxCursor INTO @tabname, @schema, @idxname, @avgfrag, @idxtype
	END

	CLOSE IdxCursor
	DEALLOCATE IdxCursor

	/*** Anschließend werden die Indizes mit einer Fragmentierung von weniger als @fraglevel% reorganisiert ***/
	IF @debugmode = 1 PRINT 'Debug mode is enabled! No statements will be executed!'
	PRINT 'Searching for indexes with a fragmentation betweem ' + CONVERT(VARCHAR, @fraglevel) + ' % and 30 % for online reorganization...' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)

	-- create cursor within dyn. sql statment to avoid parsing error with missing 'sys.dm_db_index_physical_stats'
	-- on SQL 2000 compliant databases
	SET @query =	'DECLARE IdxCursor CURSOR GLOBAL READ_ONLY FOR ' + 
					'SELECT DISTINCT o.name tabname, s.name [schema], i.name idxname, a.avg_fragmentation_in_percent, a.index_type_desc ' + 
					'FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL , ''LIMITED'') a ' + 
					'INNER JOIN sys.objects o ON a.object_id = o.object_id ' + 
					'INNER JOIN sys.schemas s ON o.schema_id = s.schema_id ' + 
					'INNER JOIN sys.indexes i ON o.object_id = i.object_id AND a.index_id = i.index_id ' + 
					'WHERE avg_fragmentation_in_percent between ' + CONVERT(VARCHAR, @fraglevel) + ' AND 30 ' +
					'AND a.page_count > ' + CONVERT(VARCHAR, @pagecount_threshold) + ' ' +
					'AND index_type_desc <> ''HEAP'' ' + 
					'AND i.allow_page_locks = 1 ' + 
					'ORDER BY a.index_type_desc, a.avg_fragmentation_in_percent desc; ' -- order by clustered indexes first
	
	EXEC (@query)

	OPEN IdxCursor
	FETCH NEXT FROM IdxCursor INTO @tabname, @schema, @idxname, @avgfrag, @idxtype
	WHILE ( @@fetch_status <> -1 )
	BEGIN
		BEGIN TRY
			PRINT 'Fragmentation of ' + @idxtype + ' ' + @idxname + ' in ' + @schema + '.' + @tabname + ': ' + 
				  CONVERT(VARCHAR, @avgfrag) + '. Will be reorganized.'
			PRINT 'ALTER INDEX ' + @idxname + ' ON ' + @schema + '.' + @tabname + ' REORGANIZE;' + CHAR(13) + CHAR(10) + CHAR(13) + CHAR(10)
			IF @debugmode = 0
			BEGIN 
				EXEC ('ALTER INDEX ' + @idxname + ' ON ' + @schema + '.' + @tabname + ' REORGANIZE;')
			END

		END TRY
		BEGIN CATCH --resume if index reorganization wasn't successful
			PRINT CONVERT(VARCHAR, ERROR_Number()) + ': ' + ERROR_MESSAGE()
		END CATCH
		FETCH NEXT FROM IdxCursor INTO @tabname, @schema, @idxname, @avgfrag, @idxtype
	END

	CLOSE IdxCursor
	DEALLOCATE IdxCursor

END


PRINT 'Defragmentation Job finished.'
IF EXISTS (SELECT 1
				FROM sys.database_files 
				WHERE TYPE = 1 -- logfiles
				AND (size / 128) > @logsize_threshold)
BEGIN
	SET @logsize = (SELECT TOP 1 (size / 128) LogSize FROM sys.database_files WHERE TYPE = 1)
	PRINT 'Current Logsize is ' + convert(varchar, @logsize) + ' MB.'
	PRINT 'Please check logfiles and try manual backup and shrink...'
END
go

-- Aktualisierung Statistiken
sp_updatestats
go
