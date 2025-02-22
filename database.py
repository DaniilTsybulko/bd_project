import psycopg2
from psycopg2 import Error
from contextlib import contextmanager
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DatabaseConnection:
    def __init__(self, config):
        self.config = config
    
    @contextmanager
    def get_cursor(self):
        conn = None
        try:
            conn = psycopg2.connect(**self.config)
            cursor = conn.cursor()
            yield cursor
            conn.commit()
        except Error as e:
            if conn:
                conn.rollback()
            logger.error(f"Ошибка базы данных: {e}")
            raise
        finally:
            if cursor:
                cursor.close()
            if conn:
                conn.close()

    def execute_query(self, query, params=None):
        with self.get_cursor() as cursor:
            cursor.execute(query, params)
            try:
                return cursor.fetchall()
            except psycopg2.ProgrammingError:
                return None 
