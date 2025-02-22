SET client_encoding = 'WIN1251';

-- Создание таблиц
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE venues (
    venue_id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    address TEXT NOT NULL,
    capacity INTEGER,
    contact_info TEXT,
    coordinates POINT
);

CREATE TABLE events (
    event_id SERIAL PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    venue_id INTEGER REFERENCES venues(venue_id),
    category_id INTEGER REFERENCES categories(category_id),
    event_date TIMESTAMP NOT NULL,
    duration INTEGER, -- в минутах
    price_range NUMRANGE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE tickets (
    ticket_id SERIAL PRIMARY KEY,
    event_id INTEGER REFERENCES events(event_id),
    user_id INTEGER REFERENCES users(user_id),
    purchase_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    price DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'active'
);

CREATE TABLE reviews (
    review_id SERIAL PRIMARY KEY,
    event_id INTEGER REFERENCES events(event_id),
    user_id INTEGER REFERENCES users(user_id),
    rating INTEGER CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE favorites (
    user_id INTEGER REFERENCES users(user_id),
    event_id INTEGER REFERENCES events(event_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, event_id)
);

-- Создание представления для популярных мероприятий
CREATE VIEW popular_events AS
SELECT 
    e.*,
    COUNT(DISTINCT t.ticket_id) as tickets_sold,
    AVG(r.rating) as avg_rating
FROM events e
LEFT JOIN tickets t ON e.event_id = t.event_id
LEFT JOIN reviews r ON e.event_id = r.event_id
WHERE e.event_date > CURRENT_TIMESTAMP
GROUP BY e.event_id
HAVING COUNT(DISTINCT t.ticket_id) > 0;

-- Создание функции для поиска мероприятий
CREATE OR REPLACE FUNCTION search_events(
    p_search_query TEXT,
    p_category_id INTEGER DEFAULT NULL,
    p_venue_id INTEGER DEFAULT NULL,
    p_date_from TIMESTAMP DEFAULT NULL,
    p_date_to TIMESTAMP DEFAULT NULL
) RETURNS TABLE (
    event_id INTEGER,
    title VARCHAR(200),
    description TEXT,
    event_date TIMESTAMP,
    venue_name VARCHAR(100),
    category_name VARCHAR(50),
    price_range NUMRANGE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        e.event_id,
        e.title,
        e.description,
        e.event_date,
        v.name as venue_name,
        c.name as category_name,
        e.price_range
    FROM events e
    JOIN venues v ON e.venue_id = v.venue_id
    JOIN categories c ON e.category_id = c.category_id
    WHERE (p_search_query IS NULL OR 
           e.title ILIKE '%' || p_search_query || '%' OR 
           e.description ILIKE '%' || p_search_query || '%')
    AND (p_category_id IS NULL OR e.category_id = p_category_id)
    AND (p_venue_id IS NULL OR e.venue_id = p_venue_id)
    AND (p_date_from IS NULL OR e.event_date >= p_date_from)
    AND (p_date_to IS NULL OR e.event_date <= p_date_to)
    AND e.event_date > CURRENT_TIMESTAMP
    ORDER BY e.event_date;
END;
$$ LANGUAGE plpgsql;

-- Триггер для проверки доступности билетов
CREATE OR REPLACE FUNCTION check_ticket_availability()
RETURNS TRIGGER AS $$
DECLARE
    tickets_sold INTEGER;
    venue_capacity INTEGER;
BEGIN
    SELECT COUNT(*) INTO tickets_sold
    FROM tickets
    WHERE event_id = NEW.event_id AND status = 'active';
    
    SELECT v.capacity INTO venue_capacity
    FROM events e
    JOIN venues v ON e.venue_id = v.venue_id
    WHERE e.event_id = NEW.event_id;
    
    IF tickets_sold >= venue_capacity THEN
        RAISE EXCEPTION 'Нет доступных билетов на это мероприятие';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER check_ticket_availability_trigger
BEFORE INSERT ON tickets
FOR EACH ROW
EXECUTE FUNCTION check_ticket_availability();

-- Создание функции для получения информации о доступных билетах
CREATE OR REPLACE FUNCTION get_available_tickets(p_event_id INTEGER)
RETURNS TABLE (
    available_tickets INTEGER,
    total_capacity INTEGER,
    min_price DECIMAL,
    max_price DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        v.capacity - COALESCE(COUNT(t.ticket_id), 0)::INTEGER as available_tickets,
        v.capacity as total_capacity,
        MIN(t.price) as min_price,
        MAX(t.price) as max_price
    FROM events e
    JOIN venues v ON e.venue_id = v.venue_id
    LEFT JOIN tickets t ON e.event_id = t.event_id AND t.status = 'active'
    WHERE e.event_id = p_event_id
    GROUP BY v.capacity;
END;
$$ LANGUAGE plpgsql;

-- Создание функции для получения комментариев к мероприятию
CREATE OR REPLACE FUNCTION get_event_reviews(p_event_id INTEGER)
RETURNS TABLE (
    username VARCHAR(50),
    rating INTEGER,
    comment TEXT,
    created_at TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.username,
        r.rating,
        r.comment,
        r.created_at
    FROM reviews r
    JOIN users u ON r.user_id = u.user_id
    WHERE r.event_id = p_event_id
    ORDER BY r.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Создание функции для подсчета избранного
CREATE OR REPLACE FUNCTION get_favorites_count(p_event_id INTEGER)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM favorites
        WHERE event_id = p_event_id
    );
END;
$$ LANGUAGE plpgsql;

-- После существующего кода добавим примеры данных

-- Заполнение категорий
INSERT INTO categories (name, description) VALUES
    ('concerts', 'Live music of various genres'),
    ('theatre', 'Theatre performances and shows'),
    ('exhibitions', 'Art and historical exhibitions'),
    ('festivals', 'Large-scale cultural events'),
    ('master_classes', 'Art education events');

-- Заполнение площадок
INSERT INTO venues (name, address, capacity, contact_info, coordinates) VALUES
    ('Grand Concert Hall', 'Central Street, 1', 1000, 'tel: +7 (999) 123-45-67', point(59.9343, 30.3351)),
    ('City Theatre', 'Arts Avenue, 15', 500, 'tel: +7 (999) 234-56-78', point(59.9343, 30.3351)),
    ('Exhibition Center', 'Museum Street, 8', 300, 'tel: +7 (999) 345-67-89', point(59.9343, 30.3351)),
    ('Cultural Center', 'Creative Square, 3', 800, 'tel: +7 (999) 456-78-90', point(59.9343, 30.3351)),
    ('Art Space', 'Modern Street, 12', 200, 'tel: +7 (999) 567-89-01', point(59.9343, 30.3351));

-- Заполнение мероприятий
INSERT INTO events (title, description, venue_id, category_id, event_date, duration, price_range, created_at) VALUES
    ('Symphony Orchestra', 'Classical music performed by the city symphony orchestra', 1, 1, 
     CURRENT_TIMESTAMP + interval '7 days', 120, numrange(1000, 5000), CURRENT_TIMESTAMP),
    ('Romeo and Juliet', 'Classical production of Shakespeare''s famous tragedy', 2, 2,
     CURRENT_TIMESTAMP + interval '14 days', 180, numrange(800, 3000), CURRENT_TIMESTAMP),
    ('Modern Art XXI Century', 'Exhibition of contemporary artists', 3, 3,
     CURRENT_TIMESTAMP + interval '5 days', 480, numrange(500, 1000), CURRENT_TIMESTAMP),
    ('Street Culture Festival', 'Large-scale city festival', 4, 4,
     CURRENT_TIMESTAMP + interval '30 days', 720, numrange(300, 1000), CURRENT_TIMESTAMP),
    ('Painting Workshop', 'Learning the basics of oil painting', 5, 5,
     CURRENT_TIMESTAMP + interval '10 days', 180, numrange(2000, 2000), CURRENT_TIMESTAMP);

-- Создание тестовых пользователей
INSERT INTO users (username, email, password_hash, created_at) VALUES
    ('ivan123', 'ivan@example.com', 'hash123', CURRENT_TIMESTAMP),
    ('maria_art', 'maria@example.com', 'hash456', CURRENT_TIMESTAMP),
    ('alex_culture', 'alex@example.com', 'hash789', CURRENT_TIMESTAMP);

-- После успешной вставки событий, добавляем билеты
INSERT INTO tickets (event_id, user_id, price, status) VALUES
    (1, 1, 3000.00, 'active'),
    (1, 2, 3000.00, 'active'),
    (2, 1, 1500.00, 'active'),
    (3, 3, 500.00, 'active'),
    (4, 2, 500.00, 'active');

INSERT INTO reviews (event_id, user_id, rating, comment) VALUES
    (1, 1, 5, 'Amazing concert! Will definitely come again.'),
    (2, 2, 4, 'Great performance, the actors were brilliant.'),
    (3, 3, 5, 'Interesting exhibition with many unique works.'),
    (1, 2, 4, 'Excellent performance of classical pieces.');

INSERT INTO favorites (user_id, event_id) VALUES
    (1, 1),
    (1, 2),
    (2, 1),
    (3, 3); 
