/***
	Skript zur Erteilung der Execute-/Select-Rechte auf SPs und Funktionen für einen angegebenen Benutzer
***/

-- Bitte Datenbankkontext festlegen
USE [<dbname, SYSNAME, VITA_APPLICATIONS_E_08>]
GO

DECLARE @principal SYSNAME
-- Hier bitte die passende AD-Gruppe, bzw. den passenden AD- oder DB-Benutzer eintragen
SET @principal = '<BenutzerOderGruppe, SYSNAME, USERBGVM\UU-00-SQL-E08-Anwender>' --USERBGVM\UU-00-SQL-I08-Anwender --USERBGVM\UU-00-SQL-T08-Anwender

IF (SELECT COUNT(1) FROM SYS.DATABASE_PRINCIPALS WHERE name = @principal) = 0
BEGIN
	DECLARE @dbname SYSNAME
	SET @dbname = DB_NAME()
	RAISERROR('Benutzer oder Gruppe [%s] ist in der Datenbank [%s] nicht vorhanden!', 11, 1, @principal, @dbname)
END
ELSE
BEGIN
	DECLARE @sqlcmd NVARCHAR(MAX), @crlf CHAR(2)
	SET @crlf = CHAR(13) + CHAR(10)
	SET @sqlcmd = ''

	SELECT @sqlcmd = @sqlcmd + 
			CASE 
				WHEN (SPECIFIC_NAME LIKE 'USP_%') OR 
						((SPECIFIC_NAME LIKE 'UDF_%' OR SPECIFIC_NAME LIKE 'UFN_%') AND DATA_TYPE <> 'TABLE')
				THEN 'grant execute on [' + SPECIFIC_SCHEMA + '].[' + SPECIFIC_NAME + '] to [' + @principal + ']' 
				WHEN SPECIFIC_NAME LIKE 'UDF_%' OR SPECIFIC_NAME LIKE 'UFN_%' AND DATA_TYPE = 'TABLE' 
				THEN 'grant select on [' + SPECIFIC_SCHEMA + '].[' + SPECIFIC_NAME + '] to [' + @principal + ']'
				ELSE '' END + @crlf 
				FROM INFORMATION_SCHEMA.ROUTINES
				WHERE (SPECIFIC_NAME LIKE 'USP_%' OR SPECIFIC_NAME LIKE 'UDF_%' OR SPECIFIC_NAME LIKE 'UFN_%' )

	-- Grant Execs für UDTs
	SELECT @sqlcmd = @sqlcmd + 'grant execute on type::[' + SCHEMA_NAME(SCHEMA_ID) + '].[' + name + '] to [' + @principal + ']' + @crlf
	FROM sys.table_types
	
	EXEC(@sqlcmd)

	/*** Da die Ausgabe von Strings auf 4000 begrenzt ist, wird der erstellte Text in 4000er-Abschnitten ausgegeben. Damit nicht mitten im
		 Command umgebrochen wird, wird genau beim Zeilenumbruch getrennt. ***/
	WHILE @sqlcmd <> ''
	BEGIN
		PRINT REVERSE(SUBSTRING(REVERSE(LEFT(@sqlcmd, 4000)), CHARINDEX(CHAR(13), REVERSE(LEFT(@sqlcmd, 4000)))-1, LEN(REVERSE(LEFT(@sqlcmd, 4000)))))
		SET @sqlcmd = SUBSTRING(@sqlcmd, LEN(REVERSE(SUBSTRING(REVERSE(LEFT(@sqlcmd, 4000)), CHARINDEX(CHAR(13), REVERSE(LEFT(@sqlcmd, 4000)))-1, LEN(REVERSE(LEFT(@sqlcmd, 4000)))))) + 1, len(@sqlcmd))
	END
	
END


