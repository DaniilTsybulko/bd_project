import streamlit as st
import psycopg2
from datetime import datetime, timedelta
from decimal import Decimal
import pandas as pd
import sys
import locale
from psycopg2.extensions import register_type, UNICODE, UNICODEARRAY

sys.stdout.recoding = 'utf-8'
locale.setlocale(locale.LC_ALL, 'ru_RU.UTF-8')

DB_CONFIG = {
    "dbname": "cultural_events",
    "user": "postgres",
    "password": "1234",  
    "host": "localhost",
    "port": "5432",
    "client_encoding": 'WIN1251'
}

CATEGORY_TRANSLATIONS = {
    'concerts': 'Concerts',
    'theatre': 'Theatre',
    'exhibitions': 'Exhibitions',
    'festivals': 'Festivals',
    'master_classes': 'Master Classes'
}

def get_db_connection():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        register_type(UNICODE, conn)
        register_type(UNICODEARRAY, conn)
        return conn
    except Exception as e:
        st.error(f"Ошибка подключения к базе данных: {e}")
        return None


def execute_query(query, params=None, fetch=True):
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute(query, params)
                if fetch:
                    result = cur.fetchall()
                    return result
                conn.commit()
        except Exception as e:
            st.error(f"Ошибка выполнения запроса: {e}")
            return None
        finally:
            conn.close()
    return None

# Функция для форматирования ценового диапазона
def format_price_range(numrange):
    if numrange is None:
        return "Цена не указана"
    # NumericRange имеет атрибуты lower и upper
    lower = int(numrange.lower) if numrange.lower is not None else 0
    upper = int(numrange.upper) if numrange.upper is not None else lower
    if lower == upper:
        return f"Цена: {lower} руб."
    return f"Цена: {lower}-{upper} руб."

# Добавьте после существующих функций
def get_ticket_info(event_id):
    query = """
    SELECT * FROM get_available_tickets(%s)
    """
    result = execute_query(query, (event_id,))
    if result and result[0]:
        available, capacity, min_price, max_price = result[0]
        
        col1, col2 = st.columns(2)
        with col1:
            st.metric("Available Tickets", f"{available} of {capacity}")
        with col2:
            if min_price is not None and max_price is not None:
                if min_price == max_price:
                    price_text = f"${min_price}"
                else:
                    price_text = f"${min_price} - ${max_price}"
                st.metric("Ticket Price", price_text)
            else:
                st.write("Price information not available")
        
        if available > 0:
            if st.button("Buy Ticket", key=f"buy_ticket_{event_id}"):
                st.info("Ticket purchase will be available in the next version")
        else:
            st.error("Sold Out")
    else:
        st.error("Failed to get ticket information")

def display_reviews(event_id):
    query = """
    SELECT * FROM get_event_reviews(%s)
    """
    reviews = execute_query(query, (event_id,))
    
    st.write("### Reviews")
    
    if reviews and len(reviews) > 0:
        for review in reviews:
            username, rating, comment, created_at = review
            with st.container():
                col1, col2 = st.columns([4, 1])
                with col1:
                    st.write(f"**{username}**")
                    st.write(comment)
                with col2:
                    st.write("⭐" * rating)
                    st.write(created_at.strftime("%Y-%m-%d"))
                st.divider()
    else:
        st.info("No reviews yet for this event")
    
    if st.button("Write Review", key=f"write_review_{event_id}"):
        st.info("Review writing will be available in the next version")

def display_favorites_count(event_id):
    query = """
    SELECT get_favorites_count(%s)
    """
    result = execute_query(query, (event_id,))
    if result and result[0]:
        count = result[0][0]
        st.metric("Added to Favorites", f"{count} {'user' if count == 1 else 'users'}")
        if st.button("Add to Favorites", key=f"add_favorite_{event_id}"):
            st.info("Adding to favorites will be available in the next version")

def main():
    st.title("Cultural Events Search")
    
    with st.sidebar:
        st.header("Filters")
        
        search_query = st.text_input("Search by name")
        
        # Получаем список категорий
        categories_query = "SELECT category_id, name FROM categories"
        categories = execute_query(categories_query)
        
        if categories is None:
            st.error("Database connection error")
            category_options = ["All Categories"]
            categories = []
        else:
            category_options = ["All Categories"] + [CATEGORY_TRANSLATIONS.get(cat[1], cat[1]) for cat in categories]
        
        selected_category = st.selectbox("Category", category_options)
        
        # Добавляем выбор площадки
        venues_query = "SELECT venue_id, name FROM venues"
        venues = execute_query(venues_query)
        
        if venues is None:
            st.error("Failed to load venues")
            venue_options = ["All Venues"]
            venues = []
        else:
            venue_options = ["All Venues"] + [venue[1] for venue in venues]
        
        selected_venue = st.selectbox("Venue", venue_options)
        
        date_from = st.date_input("Start Date", min_value=datetime.now().date())
        date_to = st.date_input("End Date", 
                               min_value=date_from,
                               value=date_from + timedelta(days=30))
        
        search_button = st.button("Search Events")
    
    if search_button:
        category_id = None
        if selected_category != "All Categories" and categories:
            original_category = [k for k, v in CATEGORY_TRANSLATIONS.items() if v == selected_category][0]
            category_id = [cat[0] for cat in categories if cat[1] == original_category][0]
        
        venue_id = None
        if selected_venue != "All Venues" and venues:
            venue_id = [venue[0] for venue in venues if venue[1] == selected_venue][0]
        
        search_params = {
            "search_query": search_query if search_query else None,
            "category_id": category_id,
            "venue_id": venue_id,  # Добавляем параметр площадки
            "date_from": datetime.combine(date_from, datetime.min.time()),
            "date_to": datetime.combine(date_to, datetime.max.time())
        }
        
        query = """
        SELECT * FROM search_events(%(search_query)s, %(category_id)s, %(venue_id)s, %(date_from)s, %(date_to)s)
        """
        
        results = execute_query(query, search_params)
        
        if results:
            for event in results:
                with st.container():
                    col1, col2 = st.columns([2, 1])
                    with col1:
                        st.subheader(event[1])
                        st.write(event[2])
                        st.write(f"Venue: {event[4]}")
                        st.write(f"Category: {CATEGORY_TRANSLATIONS.get(event[5], event[5])}")
                    with col2:
                        st.write(f"Date: {event[3].strftime('%Y-%m-%d %H:%M')}")
                        display_favorites_count(event[0])
                    
                    get_ticket_info(event[0])
                    display_reviews(event[0])
                    st.divider()
        else:
            st.info("No events found")

if __name__ == "__main__":
    main() 
