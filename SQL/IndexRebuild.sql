DECLARE @ExecuteDDL BIT
DECLARE @IndexRebuild BIT
DECLARE @SPECIFIC_SCHEMA SYSNAME

-- Festlegen, ob Befehle direkt ausgeführt werden sollen
SET @ExecuteDDL = 1

-- Reorg oder Rebuild
SET @IndexRebuild = 1

-- Schema festlegen (SQL-Wildcards erlaubt)
SET @SPECIFIC_SCHEMA = '%'

--------------------------------------------------------------------------

--
-- Indizes
--

DECLARE @cmd NVARCHAR(1000) 
DECLARE   
   @IX_Schema sysname,   
   @IX_Table sysname,  
   @IX_Name sysname

DECLARE cursor_spk CURSOR FOR   
	select sch.name as IX_Schema, obj.name as IX_Table, idx.name as IX_Name
	from sys.indexes as idx
		inner join sys.objects as obj on idx.object_id = obj.object_id
		inner join sys.schemas as sch on obj.schema_id = sch.schema_id
	where idx.[name] like 'IX_%'
		and sch.name like @SPECIFIC_SCHEMA
	order by sch.name, obj.name, idx.name

OPEN cursor_spk

FETCH NEXT FROM cursor_spk INTO @IX_Schema, @IX_Table, @IX_Name
      
WHILE @@FETCH_STATUS = 0   
BEGIN   
	IF ( @IndexRebuild = 1 )
		SET @cmd = 'ALTER INDEX [' + @IX_Name + '] on [' + @IX_Schema + '].[' + @IX_Table + '] REBUILD'
	ELSE
		SET @cmd = 'ALTER INDEX [' + @IX_Name + '] on [' + @IX_Schema + '].[' + @IX_Table + '] REORG'
	
	PRINT @cmd  

	IF ( @ExecuteDDL = 1 )
		exec (@cmd)

	FETCH NEXT FROM cursor_spk INTO @IX_Schema, @IX_Table, @IX_Name
END  

CLOSE cursor_spk
DEALLOCATE cursor_spk
GO
