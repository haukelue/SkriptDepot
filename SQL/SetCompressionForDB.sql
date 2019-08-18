DECLARE @ExecuteDDL BIT
DECLARE @CompressionType SYSNAME
DECLARE @SPECIFIC_SCHEMA SYSNAME

-- Festlegen, ob Befehle direkt ausgeführt werden sollen
SET @ExecuteDDL = 1

-- ROW, PAGE oder NONE
SET @CompressionType  = 'PAGE'

-- Schema festlegen (SQL-Wildcards erlaubt)
SET @SPECIFIC_SCHEMA = '%'

--------------------------------------------------------------------------

DECLARE tableCur CURSOR FAST_FORWARD FOR
SELECT '[' + TABLE_SCHEMA + '].[' + TABLE_NAME + ']' AS tablename
FROM INFORMATION_SCHEMA.TABLES
WHERE 
	TABLE_SCHEMA LIKE @SPECIFIC_SCHEMA AND
	TABLE_TYPE = 'BASE TABLE'
	
DECLARE @tablename SYSNAME
OPEN tableCur

FETCH NEXT FROM tableCur INTO @tablename

WHILE (@@fetch_status <> -1)
BEGIN
	IF (@@fetch_status <> -2)
	BEGIN
		print 'ALTER TABLE ' + @tablename + ' REBUILD WITH (DATA_COMPRESSION=' + @CompressionType + ')'

		IF ( @ExecuteDDL = 1 )
		BEGIN
			exec ('ALTER TABLE ' + @tablename + ' REBUILD WITH (DATA_COMPRESSION=' + @CompressionType + ')')
		END	
	END
	
	FETCH NEXT FROM tableCur INTO @tablename
END

CLOSE tableCur
DEALLOCATE tableCur

GO
