SELECT object_name, object_type, status FROM user_objects WHERE status != 'VALID';
SELECT name, type, text FROM user_errors;
BEGIN
  DBMS_UTILITY.COMPILE_SCHEMA(USER);
END;
/
SELECT object_name, object_type, status FROM user_objects WHERE status != 'VALID';
EXIT;
