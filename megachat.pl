#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::Util qw(secure_compare);
use Crypt::Eksblowfish::Bcrypt qw(bcrypt);
use Time::Piece;
use Data::UUID;
use File::Basename;
use File::Spec;
use URI::Escape qw(uri_escape_utf8);
use Mojo::JSON qw(encode_json decode_json);
use Mojo::IOLoop;

# Устанавливаем кодировку для избежания проблем с широкими символами
use utf8;
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# Подключение плагинов
plugin 'Database' => {
    dsn => 'dbi:SQLite:dbname=megachat.db',
    options => { 
        RaiseError => 1, 
        AutoCommit => 1,
        sqlite_unicode => 1
    }
};

# WebSocket подключения
my %websocket_connections = ();
my %user_sessions = ();

# Простая аутентификация через сессии
sub authenticate_user {
    my ($c, $username, $password) = @_;
    my $db = $c->db;
    my $user = $db->selectrow_hashref(
        'SELECT * FROM users WHERE username = ?', 
        undef, $username
    );
    
    if ($user) {
        # Простая проверка пароля для тестирования
        if ($user->{password_hash} eq $password) {
            return $user;
        }
    }
    return undef;
}

sub is_user_authenticated {
    my $c = shift;
    return $c->session('user_id') ? 1 : 0;
}

sub current_user {
    my $c = shift;
    return undef unless is_user_authenticated($c);
    my $db = $c->db;
    return $db->selectrow_hashref(
        'SELECT * FROM users WHERE id = ?', 
        undef, $c->session('user_id')
    );
}

sub format_file_size {
    my $size = shift;
    return '0 B' if $size == 0;
    
    my @units = ('B', 'KB', 'MB', 'GB', 'TB');
    my $unit_index = 0;
    
    while ($size >= 1024 && $unit_index < $#units) {
        $size /= 1024;
        $unit_index++;
    }
    
    return sprintf('%.1f %s', $size, $units[$unit_index]);
}

# Настройка безопасности
app->secrets(['megachat_secret_key_change_in_production']);

# Инициализация базы данных
app->hook(before_server_start => sub {
    my $db = app->db;
    
    # Создание таблиц
    $db->do(q{
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username VARCHAR(50) UNIQUE NOT NULL,
            password_hash VARCHAR(255) NOT NULL,
            password_salt VARCHAR(255) NOT NULL,
            email VARCHAR(100),
            avatar_url VARCHAR(255),
            status VARCHAR(20) DEFAULT 'offline',
            last_seen INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        )
    });
    
    # Чаты (включая специальные)
    $db->do(q{
        CREATE TABLE IF NOT EXISTS conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name VARCHAR(255),
            type VARCHAR(20) NOT NULL, -- private, group, notes, files
            description TEXT,
            created_by INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (created_by) REFERENCES users (id)
        )
    });
    
    # Участники чатов
    $db->do(q{
        CREATE TABLE IF NOT EXISTS conversation_participants (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            joined_at INTEGER NOT NULL,
            FOREIGN KEY (conversation_id) REFERENCES conversations (id),
            FOREIGN KEY (user_id) REFERENCES users (id),
            UNIQUE(conversation_id, user_id)
        )
    });
    
    # Сообщения (все типы)
    $db->do(q{
        CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER NOT NULL,
            sender_id INTEGER NOT NULL,
            content TEXT,
            message_type VARCHAR(20) DEFAULT 'text', -- text, file, note, image, voice
            file_id INTEGER, -- для файловых сообщений
            note_id INTEGER, -- для заметок
            reply_to_id INTEGER, -- ответ на сообщение
            created_at INTEGER NOT NULL,
            FOREIGN KEY (conversation_id) REFERENCES conversations (id),
            FOREIGN KEY (sender_id) REFERENCES users (id),
            FOREIGN KEY (file_id) REFERENCES files (id),
            FOREIGN KEY (note_id) REFERENCES notes (id),
            FOREIGN KEY (reply_to_id) REFERENCES messages (id)
        )
    });
    
    # Файлы
    $db->do(q{
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            original_name VARCHAR(255) NOT NULL,
            stored_name VARCHAR(255) NOT NULL,
            file_size INTEGER NOT NULL,
            mime_type VARCHAR(100),
            thumbnail_url VARCHAR(255),
            created_at INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users (id)
        )
    });
    
    # Заметки
    $db->do(q{
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            title VARCHAR(255) NOT NULL,
            content TEXT,
            color VARCHAR(7),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users (id)
        )
    });
    
    # Реакции на сообщения
    $db->do(q{
        CREATE TABLE IF NOT EXISTS message_reactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            message_id INTEGER NOT NULL,
            user_id INTEGER NOT NULL,
            emoji VARCHAR(10) NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (message_id) REFERENCES messages (id),
            FOREIGN KEY (user_id) REFERENCES users (id),
            UNIQUE(message_id, user_id, emoji)
        )
    });
    
    # Создание индексов
    $db->do('CREATE INDEX IF NOT EXISTS idx_conversations_type ON conversations (type)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_conversations_created_by ON conversations (created_by)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation_id ON conversation_participants (conversation_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id ON conversation_participants (user_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages (conversation_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_messages_sender_id ON messages (sender_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages (created_at)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_files_user_id ON files (user_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_notes_user_id ON notes (user_id)');
    $db->do('CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id ON message_reactions (message_id)');
    
    # Создание админа по умолчанию
    my $admin_exists = $db->selectrow_array('SELECT COUNT(*) FROM users WHERE username = ?', undef, 'admin');
    unless ($admin_exists) {
        my $salt = 'simple_salt_' . time();
        my $hash = 'admin123';
        
        $db->do(
            'INSERT INTO users (username, password_hash, password_salt, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
            undef, 'admin', $hash, $salt, time(), time()
        );
        
        print "Создан пользователь admin с паролем admin123\n";
    }
    
    # Создание специальных чатов для каждого пользователя
    my $users = $db->selectall_arrayref('SELECT id FROM users', { Slice => {} });
    for my $user (@$users) {
        # Проверяем, есть ли уже специальные чаты
        my $notes_chat = $db->selectrow_array(
            'SELECT id FROM conversations WHERE type = ? AND created_by = ?', 
            undef, 'notes', $user->{id}
        );
        
        unless ($notes_chat) {
            my $now = time();
            $db->do(
                'INSERT INTO conversations (name, type, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
                undef, 'Избранные заметки', 'notes', 'Ваши личные заметки', $user->{id}, $now, $now
            );
            
            my $notes_id = $db->last_insert_id('', '', '', '');
            $db->do(
                'INSERT INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
                undef, $notes_id, $user->{id}, $now
            );
        }
        
        my $files_chat = $db->selectrow_array(
            'SELECT id FROM conversations WHERE type = ? AND created_by = ?', 
            undef, 'files', $user->{id}
        );
        
        unless ($files_chat) {
            my $now = time();
            $db->do(
                'INSERT INTO conversations (name, type, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
                undef, 'Избранные файлы', 'files', 'Ваши загруженные файлы', $user->{id}, $now, $now
            );
            
            my $files_id = $db->last_insert_id('', '', '', '');
            $db->do(
                'INSERT INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
                undef, $files_id, $user->{id}, $now
            );
        }
    }
});

# Middleware для проверки аутентификации
under sub {
    my $c = shift;
    return 1 if $c->req->url->path =~ m{^/(login|register|api/auth|download|static)};
    return $c->redirect_to('login') unless is_user_authenticated($c);
    1;
};

# Статические файлы - используем директорию public
app->static->paths(['public']);

# Главная страница
get '/' => sub {
    my $c = shift;
    $c->render(template => 'index');
};

# API маршруты
my $api = app->routes->under('/api');

# Аутентификация API
$api->get('/auth/check' => sub {
    my $c = shift;
    if (is_user_authenticated($c)) {
        my $user = current_user($c);
        $c->render(json => { 
            success => 1, 
            user => { 
                id => $user->{id},
                username => $user->{username},
                status => $user->{status} || 'offline'
            }
        });
    } else {
        $c->render(json => { success => 0 }, status => 401);
    }
});

$api->post('/auth/login' => sub {
    my $c = shift;
    my $data = $c->req->json;
    
    my $user = authenticate_user($c, $data->{username}, $data->{password});
    if ($user) {
        $c->session(user_id => $user->{id});
        $c->render(json => { 
            success => 1, 
            user => { 
                id => $user->{id},
                username => $user->{username},
                status => $user->{status} || 'offline'
            }
        });
    } else {
        $c->render(json => { success => 0, error => 'Invalid credentials' }, status => 401);
    }
});

$api->post('/auth/logout' => sub {
    my $c = shift;
    $c->session(expires => 1);
    $c->render(json => { success => 1 });
});

$api->post('/auth/register' => sub {
    my $c = shift;
    my $data = $c->req->json;
    my $db = $c->db;
    
    # Валидация
    unless ($data->{username} && $data->{password}) {
        return $c->render(json => { success => 0, error => 'Username and password are required' }, status => 400);
    }
    
    if (length($data->{username}) < 3 || length($data->{username}) > 50) {
        return $c->render(json => { success => 0, error => 'Username must be 3-50 characters' }, status => 400);
    }
    
    if (length($data->{password}) < 3) {
        return $c->render(json => { success => 0, error => 'Password must be at least 3 characters' }, status => 400);
    }
    
    # Проверка существования пользователя
    my $existing = $db->selectrow_array('SELECT COUNT(*) FROM users WHERE username = ?', undef, $data->{username});
    if ($existing) {
        return $c->render(json => { success => 0, error => 'Username already exists' }, status => 400);
    }
    
    # Создание пользователя
    my $salt = 'simple_salt_' . time() . '_' . rand(1000);
    my $hash = $data->{password};
    
    $db->do(
        'INSERT INTO users (username, password_hash, password_salt, email, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        undef, $data->{username}, $hash, $salt, $data->{email} || '', time(), time()
    );
    
    my $user_id = $db->last_insert_id('', '', '', '');
    unless ($user_id) {
        my $last_id = $db->selectrow_array('SELECT id FROM users WHERE username = ? ORDER BY id DESC LIMIT 1', undef, $data->{username});
        $user_id = $last_id if $last_id;
    }
    
    # Создаем специальные чаты для нового пользователя
    my $now = time();
    
    # Чат для заметок
    $db->do(
        'INSERT INTO conversations (name, type, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        undef, 'Избранные заметки', 'notes', 'Ваши личные заметки', $user_id, $now, $now
    );
    my $notes_id = $db->last_insert_id('', '', '', '');
    $db->do(
        'INSERT INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
        undef, $notes_id, $user_id, $now
    );
    
    # Чат для файлов
    $db->do(
        'INSERT INTO conversations (name, type, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        undef, 'Избранные файлы', 'files', 'Ваши загруженные файлы', $user_id, $now, $now
    );
    my $files_id = $db->last_insert_id('', '', '', '');
    $db->do(
        'INSERT INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
        undef, $files_id, $user_id, $now
    );
    
    # Автоматический вход после регистрации
    $c->session(user_id => $user_id);
    $c->render(json => { 
        success => 1, 
        user => { 
            id => $user_id,
            username => $data->{username},
            status => 'offline'
        }
    });
});

# API для чатов
$api->get('/conversations' => sub {
    my $c = shift;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Получаем чаты пользователя с последними сообщениями
    my $conversations = $db->selectall_arrayref(q{
        SELECT DISTINCT c.id, c.name, c.type, c.description, c.created_at, c.updated_at,
               u.username as created_by_username,
               m.content as last_message,
               m.created_at as last_message_time,
               m.sender_id as last_message_sender_id,
               m.message_type as last_message_type,
               u2.username as last_message_sender_username
        FROM conversations c
        JOIN conversation_participants cp ON c.id = cp.conversation_id
        LEFT JOIN users u ON c.created_by = u.id
        LEFT JOIN messages m ON c.id = m.conversation_id
        LEFT JOIN users u2 ON m.sender_id = u2.id
        WHERE cp.user_id = ?
        AND (m.id IS NULL OR m.id = (
            SELECT MAX(id) FROM messages WHERE conversation_id = c.id
        ))
        ORDER BY COALESCE(m.created_at, c.updated_at) DESC
    }, { Slice => {} }, $user_id);
    
    # Форматирование дат
    $_->{created_at_formatted} = localtime($_->{created_at})->strftime('%d.%m.%Y %H:%M') for @$conversations;
    $_->{updated_at_formatted} = localtime($_->{updated_at})->strftime('%d.%m.%Y %H:%M') for @$conversations;
    $_->{last_message_time_formatted} = localtime($_->{last_message_time})->strftime('%d.%m.%Y %H:%M') if $_->{last_message_time};
    
    $c->render(json => $conversations);
});

# API для получения информации о конкретном чате
$api->get('/conversations/:id' => sub {
    my $c = shift;
    my $conversation_id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что пользователь участвует в чате
    my $is_participant = $db->selectrow_array(
        'SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
        undef, $conversation_id, $user_id
    );
    
    unless ($is_participant) {
        return $c->render(json => { success => 0, error => 'Access denied' }, status => 403);
    }
    
    # Получаем информацию о чате
    my $chat = $db->selectrow_hashref(q{
        SELECT c.id, c.name, c.type, c.description, c.created_at, c.updated_at,
               u.username as created_by_username
        FROM conversations c
        LEFT JOIN users u ON c.created_by = u.id
        WHERE c.id = ?
    }, undef, $conversation_id);
    
    unless ($chat) {
        return $c->render(json => { success => 0, error => 'Chat not found' }, status => 404);
    }
    
    # Получаем участников чата
    my $participants = $db->selectall_arrayref(q{
        SELECT u.id, u.username, cp.joined_at
        FROM conversation_participants cp
        JOIN users u ON cp.user_id = u.id
        WHERE cp.conversation_id = ?
        ORDER BY u.username
    }, { Slice => {} }, $conversation_id);
    
    # Форматирование дат
    $chat->{created_at_formatted} = localtime($chat->{created_at})->strftime('%d.%m.%Y %H:%M');
    $chat->{updated_at_formatted} = localtime($chat->{updated_at})->strftime('%d.%m.%Y %H:%M');
    $_->{joined_at_formatted} = localtime($_->{joined_at})->strftime('%d.%m.%Y %H:%M') for @$participants;
    
    $chat->{participants} = $participants;
    
    $c->render(json => $chat);
});

# API для сообщений
$api->get('/conversations/:id/messages' => sub {
    my $c = shift;
    my $conversation_id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что пользователь участвует в чате
    my $is_participant = $db->selectrow_array(
        'SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
        undef, $conversation_id, $user_id
    );
    
    unless ($is_participant) {
        return $c->render(json => { success => 0, error => 'Access denied' }, status => 403);
    }
    
    # Получаем сообщения с дополнительной информацией
    my $messages = $db->selectall_arrayref(q{
        SELECT m.id, m.content, m.message_type, m.created_at, m.sender_id, m.file_id, m.note_id, m.reply_to_id,
               u.username as sender_username,
               f.original_name as file_name, f.file_size, f.mime_type, f.thumbnail_url,
               n.title as note_title, n.content as note_content, n.color as note_color
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        LEFT JOIN files f ON m.file_id = f.id
        LEFT JOIN notes n ON m.note_id = n.id
        WHERE m.conversation_id = ?
        ORDER BY m.created_at ASC
    }, { Slice => {} }, $conversation_id);
    
    # Форматирование дат и размеров файлов
    for my $message (@$messages) {
        $message->{created_at_formatted} = localtime($message->{created_at})->strftime('%d.%m.%Y %H:%M');
        if ($message->{file_size}) {
            $message->{file_size_formatted} = format_file_size($message->{file_size});
        }
    }
    
    $c->render(json => $messages);
});

$api->post('/conversations/:id/messages' => sub {
    my $c = shift;
    my $conversation_id = $c->param('id');
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что пользователь участвует в чате
    my $is_participant = $db->selectrow_array(
        'SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
        undef, $conversation_id, $user_id
    );
    
    unless ($is_participant) {
        return $c->render(json => { success => 0, error => 'Access denied' }, status => 403);
    }
    
    # Валидация
    unless ($data->{content} || $data->{file_id} || $data->{note_id}) {
        return $c->render(json => { success => 0, error => 'Message content is required' }, status => 400);
    }
    
    my $now = time();
    
    # Создаем сообщение
    $db->do(
        'INSERT INTO messages (conversation_id, sender_id, content, message_type, file_id, note_id, reply_to_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        undef, $conversation_id, $user_id, $data->{content} || '', $data->{message_type} || 'text', $data->{file_id}, $data->{note_id}, $data->{reply_to_id}, $now
    );
    
    my $message_id = $db->last_insert_id('', '', '', '');
    unless ($message_id) {
        my $last_id = $db->selectrow_array('SELECT id FROM messages WHERE conversation_id = ? ORDER BY id DESC LIMIT 1', undef, $conversation_id);
        $message_id = $last_id if $last_id;
    }
    
    # Обновляем время последнего обновления чата
    $db->do(
        'UPDATE conversations SET updated_at = ? WHERE id = ?',
        undef, $now, $conversation_id
    );
    
    # Получаем полную информацию о сообщении для WebSocket
    my $full_message = $db->selectrow_hashref(q{
        SELECT m.*, u.username as sender_username
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        WHERE m.id = ?
    }, undef, $message_id);
    
    # Форматируем дату
    $full_message->{created_at_formatted} = localtime($full_message->{created_at})->strftime('%d.%m.%Y %H:%M');
    
    # Отправляем через WebSocket
    broadcast_message($conversation_id, $full_message);
    
    $c->render(json => { success => 1, id => $message_id });
});

# API для поиска пользователей
$api->get('/users/search' => sub {
    my $c = shift;
    my $db = $c->db;
    my $query = $c->param('q') || '';
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Поиск пользователей по логину
    my $users = $db->selectall_arrayref(q{
        SELECT id, username, email, created_at, status
        FROM users
        WHERE username LIKE ? AND id != ?
        ORDER BY username
        LIMIT 20
    }, { Slice => {} }, "%$query%", $user_id);
    
    # Форматирование дат
    $_->{created_at_formatted} = localtime($_->{created_at})->strftime('%d.%m.%Y') for @$users;
    
    $c->render(json => $users);
});

# API для поллинга новых сообщений
$api->get('/conversations/:id/messages/new' => sub {
    my $c = shift;
    my $conversation_id = $c->param('id');
    my $last_message_id = $c->param('last_message_id') || 0;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что пользователь участвует в чате
    my $is_participant = $db->selectrow_array(
        'SELECT COUNT(*) FROM conversation_participants WHERE conversation_id = ? AND user_id = ?',
        undef, $conversation_id, $user_id
    );
    
    unless ($is_participant) {
        return $c->render(json => { success => 0, error => 'Access denied' }, status => 403);
    }
    
    # Получаем новые сообщения
    my $messages = $db->selectall_arrayref(q{
        SELECT m.id, m.content, m.message_type, m.created_at, m.sender_id, m.file_id, m.note_id, m.reply_to_id,
               u.username as sender_username,
               f.original_name as file_name, f.file_size, f.mime_type, f.thumbnail_url,
               n.title as note_title, n.content as note_content, n.color as note_color
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        LEFT JOIN files f ON m.file_id = f.id
        LEFT JOIN notes n ON m.note_id = n.id
        WHERE m.conversation_id = ? AND m.id > ?
        ORDER BY m.created_at ASC
    }, { Slice => {} }, $conversation_id, $last_message_id);
    
    # Форматирование дат и размеров файлов
    for my $message (@$messages) {
        $message->{created_at_formatted} = localtime($message->{created_at})->strftime('%d.%m.%Y %H:%M');
        if ($message->{file_size}) {
            $message->{file_size_formatted} = format_file_size($message->{file_size});
        }
    }
    
    $c->render(json => $messages);
});

# API для создания чатов
$api->post('/conversations' => sub {
    my $c = shift;
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    my $now = time();
    
    # Валидация
    unless ($data->{participants} && ref($data->{participants}) eq 'ARRAY' && @{$data->{participants}}) {
        return $c->render(json => { success => 0, error => 'Participants are required' }, status => 400);
    }
    
    # Проверяем, что все участники существуют
    my $participant_ids = $data->{participants};
    my $placeholders = join(',', ('?') x @$participant_ids);
    my $existing_users = $db->selectall_arrayref(
        "SELECT id FROM users WHERE id IN ($placeholders)",
        undef, @$participant_ids
    );
    
    if (@$existing_users != @$participant_ids) {
        return $c->render(json => { success => 0, error => 'Some participants not found' }, status => 400);
    }
    
    # Создаем чат
    my $conversation_type = $data->{type} || (@$participant_ids == 1 ? 'private' : 'group');
    my $conversation_name = $data->{name} || ($conversation_type eq 'private' ? undef : 'Group Chat');
    
    $db->do(
        'INSERT INTO conversations (name, type, description, created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        undef, $conversation_name, $conversation_type, $data->{description} || '', $user_id, $now, $now
    );
    
    my $conversation_id = $db->last_insert_id('', '', '', '');
    unless ($conversation_id) {
        my $last_id = $db->selectrow_array('SELECT id FROM conversations WHERE created_by = ? ORDER BY id DESC LIMIT 1', undef, $user_id);
        $conversation_id = $last_id if $last_id;
    }
    
    # Добавляем участников
    for my $participant_id (@$participant_ids) {
        $db->do(
            'INSERT INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
            undef, $conversation_id, $participant_id, $now
        );
    }
    
    # Добавляем создателя как участника
    $db->do(
        'INSERT OR IGNORE INTO conversation_participants (conversation_id, user_id, joined_at) VALUES (?, ?, ?)',
        undef, $conversation_id, $user_id, $now
    );
    
    $c->render(json => { success => 1, id => $conversation_id });
});

# API для файлов
$api->get('/files' => sub {
    my $c = shift;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    my $files = $db->selectall_arrayref(
        'SELECT id, original_name, stored_name, file_size, mime_type, thumbnail_url, created_at FROM files WHERE user_id = ? ORDER BY created_at DESC',
        { Slice => {} }, $user_id
    );
    
    # Форматирование дат и размеров файлов
    for my $file (@$files) {
        $file->{created_at_formatted} = localtime($file->{created_at})->strftime('%d.%m.%Y %H:%M');
        $file->{file_size_formatted} = format_file_size($file->{file_size});
    }
    
    $c->render(json => $files);
});

$api->put('/files/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверка принадлежности файла пользователю
    my $file = $db->selectrow_hashref(
        'SELECT * FROM files WHERE id = ? AND user_id = ?', 
        undef, $id, $user_id
    );
    
    return $c->render(json => { success => 0, error => 'File not found' }, status => 404) 
        unless $file;
    
    # Обновляем только описание файла (если добавим поле description)
    $c->render(json => { success => 1 });
});

$api->delete('/files/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Получаем информацию о файле перед удалением
    my $file = $db->selectrow_hashref(
        'SELECT * FROM files WHERE id = ? AND user_id = ?', 
        undef, $id, $user_id
    );
    
    return $c->render(json => { success => 0, error => 'File not found' }, status => 404) 
        unless $file;
    
    # Удаляем файл с диска
    my $file_path = File::Spec->catfile('files', $file->{stored_name});
    unlink $file_path if -f $file_path;
    
    # Удаляем запись из БД
    my $affected = $db->do(
        'DELETE FROM files WHERE id = ? AND user_id = ?',
        undef, $id, $user_id
    );
    
    $c->render(json => { success => 1 });
});

$api->post('/files' => sub {
    my $c = shift;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Получаем загруженный файл
    my $upload = $c->req->upload('file');
    unless ($upload) {
        return $c->render(json => { success => 0, error => 'No file uploaded' }, status => 400);
    }
    
    my $original_name = $upload->filename;
    my $file_size = $upload->size;
    my $mime_type = $upload->headers->content_type || 'application/octet-stream';
    
    # Генерируем GUID для имени файла
    my $ug = Data::UUID->new;
    my $uuid = $ug->create();
    my $stored_name = $ug->to_string($uuid);
    
    # Сохраняем файл
    my $files_dir = File::Spec->catdir('files');
    my $file_path = File::Spec->catfile($files_dir, $stored_name);
    
    unless (-d $files_dir) {
        mkdir $files_dir or die "Cannot create files directory: $!";
    }
    
    $upload->move_to($file_path);
    
    # Сохраняем информацию о файле в БД
    my $now = time();
    my $sth = $db->prepare('INSERT INTO files (user_id, original_name, stored_name, file_size, mime_type, created_at) VALUES (?, ?, ?, ?, ?, ?)');
    $sth->execute($user_id, $original_name, $stored_name, $file_size, $mime_type, $now);
    
    # Получаем ID созданной записи
    my $id = $db->last_insert_id('', '', '', '');
    unless ($id) {
        my $last_id = $db->selectrow_array('SELECT id FROM files WHERE user_id = ? ORDER BY id DESC LIMIT 1', undef, $user_id);
        $id = $last_id if $last_id;
    }
    
    $c->render(json => { success => 1, id => $id, stored_name => $stored_name, download_url => "/download/$stored_name" });
});

# API для заметок
$api->get('/notes' => sub {
    my $c = shift;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    my $notes = $db->selectall_arrayref(
        'SELECT id, title, content, color, created_at, updated_at FROM notes WHERE user_id = ? ORDER BY created_at DESC',
        { Slice => {} }, $user_id
    );
    
    # Форматирование дат
    $_->{created_at_formatted} = localtime($_->{created_at})->strftime('%d.%m.%Y %H:%M') for @$notes;
    $_->{updated_at_formatted} = localtime($_->{updated_at})->strftime('%d.%m.%Y %H:%M') for @$notes;
    
    $c->render(json => $notes);
});

$api->put('/notes/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверка принадлежности заметки пользователю
    my $note = $db->selectrow_hashref(
        'SELECT * FROM notes WHERE id = ? AND user_id = ?', 
        undef, $id, $user_id
    );
    
    return $c->render(json => { success => 0, error => 'Note not found' }, status => 404) 
        unless $note;
    
    # Валидация
    return $c->render(json => { success => 0, error => 'Title is required' }, status => 400) 
        unless $data->{title};
    
    $db->do(
        'UPDATE notes SET title = ?, content = ?, color = ?, updated_at = ? WHERE id = ? AND user_id = ?',
        undef, $data->{title}, $data->{content} || '', $data->{color} || '#ffffff', time(), $id, $user_id
    );
    
    $c->render(json => { success => 1 });
});

$api->delete('/notes/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    my $affected = $db->do(
        'DELETE FROM notes WHERE id = ? AND user_id = ?',
        undef, $id, $user_id
    );
    
    return $c->render(json => { success => 0, error => 'Note not found' }, status => 404) 
        unless $affected;
    
    $c->render(json => { success => 1 });
});

$api->post('/notes' => sub {
    my $c = shift;
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Валидация
    unless ($data->{title}) {
        return $c->render(json => { success => 0, error => 'Title is required' }, status => 400);
    }
    
    my $now = time();
    
    my $sth = $db->prepare('INSERT INTO notes (user_id, title, content, color, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)');
    $sth->execute($user_id, $data->{title}, $data->{content} || '', $data->{color} || '#ffffff', $now, $now);
    
    my $id = $db->last_insert_id('', '', '', '');
    unless ($id) {
        my $last_id = $db->selectrow_array('SELECT id FROM notes WHERE user_id = ? ORDER BY id DESC LIMIT 1', undef, $user_id);
        $id = $last_id if $last_id;
    }
    
    $c->render(json => { success => 1, id => $id });
});

# API для работы с сообщениями
$api->get('/messages/:id' => sub {
    my $c = shift;
    my $message_id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    # Получаем сообщение
    my $message = $db->selectrow_hashref(q{
        SELECT m.*, u.username as sender_username
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        WHERE m.id = ?
    }, undef, $message_id);
    
    unless ($message) {
        return $c->render(json => { success => 0, error => 'Message not found' }, status => 404);
    }
    
    $c->render(json => $message);
});

$api->put('/messages/:id' => sub {
    my $c = shift;
    my $message_id = $c->param('id');
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что сообщение принадлежит пользователю
    my $message = $db->selectrow_hashref(
        'SELECT * FROM messages WHERE id = ? AND sender_id = ?', 
        undef, $message_id, $user_id
    );
    
    unless ($message) {
        return $c->render(json => { success => 0, error => 'Message not found or not owned by user' }, status => 404);
    }
    
    # Обновляем только текстовые сообщения
    unless ($message->{message_type} eq 'text') {
        return $c->render(json => { success => 0, error => 'Only text messages can be edited' }, status => 400);
    }
    
    # Валидация
    unless ($data->{content}) {
        return $c->render(json => { success => 0, error => 'Content is required' }, status => 400);
    }
    
    $db->do(
        'UPDATE messages SET content = ?, updated_at = ? WHERE id = ? AND sender_id = ?',
        undef, $data->{content}, time(), $message_id, $user_id
    );
    
    $c->render(json => { success => 1 });
});

$api->delete('/messages/:id' => sub {
    my $c = shift;
    my $message_id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    
    # Проверяем, что сообщение принадлежит пользователю
    my $message = $db->selectrow_hashref(
        'SELECT * FROM messages WHERE id = ? AND sender_id = ?', 
        undef, $message_id, $user_id
    );
    
    unless ($message) {
        return $c->render(json => { success => 0, error => 'Message not found or not owned by user' }, status => 404);
    }
    
    # Удаляем сообщение
    $db->do(
        'DELETE FROM messages WHERE id = ? AND sender_id = ?',
        undef, $message_id, $user_id
    );
    
    $c->render(json => { success => 1 });
});

# API для реакций на сообщения
$api->get('/messages/:id/reactions' => sub {
    my $c = shift;
    my $message_id = $c->param('id');
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    # Получаем реакции на сообщение
    my $reactions = $db->selectall_arrayref(q{
        SELECT mr.id, mr.emoji, mr.created_at, u.username
        FROM message_reactions mr
        JOIN users u ON mr.user_id = u.id
        WHERE mr.message_id = ?
        ORDER BY mr.created_at ASC
    }, { Slice => {} }, $message_id);
    
    $c->render(json => $reactions);
});

$api->post('/messages/:id/reactions' => sub {
    my $c = shift;
    my $message_id = $c->param('id');
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    my $emoji = $data->{emoji};
    
    unless ($emoji) {
        return $c->render(json => { success => 0, error => 'Emoji is required' }, status => 400);
    }
    
    # Проверяем, что сообщение существует
    my $message = $db->selectrow_hashref(
        'SELECT * FROM messages WHERE id = ?', 
        undef, $message_id
    );
    
    unless ($message) {
        return $c->render(json => { success => 0, error => 'Message not found' }, status => 404);
    }
    
    # Проверяем, есть ли уже такая реакция от этого пользователя
    my $existing = $db->selectrow_hashref(
        'SELECT * FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?',
        undef, $message_id, $user_id, $emoji
    );
    
    if ($existing) {
        # Удаляем реакцию (переключение)
        $db->do(
            'DELETE FROM message_reactions WHERE message_id = ? AND user_id = ? AND emoji = ?',
            undef, $message_id, $user_id, $emoji
        );
    } else {
        # Добавляем реакцию
        $db->do(
            'INSERT INTO message_reactions (message_id, user_id, emoji, created_at) VALUES (?, ?, ?, ?)',
            undef, $message_id, $user_id, $emoji, time()
        );
    }
    
    $c->render(json => { success => 1 });
});

# API для поиска сообщений
$api->post('/messages/search' => sub {
    my $c = shift;
    my $data = $c->req->json;
    my $db = $c->db;
    
    my $user = current_user($c);
    unless ($user) {
        return $c->render(json => { success => 0, error => 'Not authenticated' }, status => 401);
    }
    
    my $user_id = $user->{id};
    my $query = $data->{query};
    my $filters = $data->{filters} || {};
    
    unless ($query) {
        return $c->render(json => { success => 0, error => 'Query is required' }, status => 400);
    }
    
    # Строим SQL запрос для поиска
    my @where_conditions = ();
    my @params = ();
    
    # Базовое условие - пользователь должен быть участником чата
    push @where_conditions, 'c.id IN (SELECT conversation_id FROM conversation_participants WHERE user_id = ?)';
    push @params, $user_id;
    
    # Условия поиска по типам сообщений
    my @type_conditions = ();
    
    if ($filters->{text}) {
        push @type_conditions, "(m.message_type = 'text' AND m.content LIKE ?)";
        push @params, "%$query%";
    }
    
    if ($filters->{files}) {
        push @type_conditions, "(m.message_type IN ('file', 'image', 'voice') AND f.original_name LIKE ?)";
        push @params, "%$query%";
    }
    
    if ($filters->{notes}) {
        push @type_conditions, "(m.message_type = 'note' AND (n.title LIKE ? OR n.content LIKE ?))";
        push @params, "%$query%", "%$query%";
    }
    
    if (@type_conditions) {
        push @where_conditions, '(' . join(' OR ', @type_conditions) . ')';
    } else {
        # Если нет фильтров, ищем везде
        push @where_conditions, "(m.content LIKE ? OR f.original_name LIKE ? OR n.title LIKE ? OR n.content LIKE ?)";
        push @params, "%$query%", "%$query%", "%$query%", "%$query%";
    }
    
    my $where_clause = join(' AND ', @where_conditions);
    
    my $search_query = qq{
        SELECT DISTINCT
            m.id,
            m.conversation_id,
            m.message_type,
            m.content,
            m.created_at,
            u.username as sender_username,
            c.name as conversation_name,
            f.original_name as file_name,
            f.file_size,
            f.stored_name,
            n.title as note_title,
            n.content as note_content,
            n.color as note_color
        FROM messages m
        JOIN users u ON m.sender_id = u.id
        JOIN conversations c ON m.conversation_id = c.id
        LEFT JOIN files f ON m.file_id = f.id
        LEFT JOIN notes n ON m.note_id = n.id
        WHERE $where_clause
        ORDER BY m.created_at DESC
        LIMIT 50
    };
    
    my $results = $db->selectall_arrayref($search_query, { Slice => {} }, @params);
    
    # Форматируем результаты
    for my $result (@$results) {
        $result->{created_at_formatted} = localtime($result->{created_at})->strftime('%d.%m.%Y %H:%M');
        if ($result->{file_size}) {
            $result->{file_size_formatted} = format_file_size($result->{file_size});
        }
    }
    
    $c->render(json => $results);
});

# WebSocket endpoint
websocket '/ws' => sub {
    my $c = shift;
    
    # Проверяем аутентификацию
    my $user = current_user($c);
    unless ($user) {
        $c->render(text => 'Unauthorized', status => 401);
        return;
    }
    
    my $user_id = $user->{id};
    my $username = $user->{username};
    
    # Добавляем подключение
    $websocket_connections{$user_id} = $c;
    $user_sessions{$user_id} = {
        username => $username,
        connected_at => time(),
        current_conversation => undef
    };
    
    # Уведомляем о подключении
    broadcast_user_status($user_id, 'online');
    
    # Обработка сообщений
    $c->on(message => sub {
        my ($c, $msg) = @_;
        
        my $data = eval { decode_json($msg) };
        if ($@) {
            $c->send(encode_json({ type => 'error', message => 'Invalid JSON' }));
            return;
        }
        
        handle_websocket_message($c, $user_id, $data);
    });
    
    # Обработка отключения
    $c->on(finish => sub {
        my ($c, $code, $reason) = @_;
        
        # Удаляем подключение
        delete $websocket_connections{$user_id};
        delete $user_sessions{$user_id};
        
        # Уведомляем об отключении
        broadcast_user_status($user_id, 'offline');
    });
    
    # Отправляем приветственное сообщение
    $c->send(encode_json({
        type => 'connected',
        user_id => $user_id,
        username => $username
    }));
};

# Обработка WebSocket сообщений
sub handle_websocket_message {
    my ($c, $user_id, $data) = @_;
    
    my $type = $data->{type};
    
    if ($type eq 'join_conversation') {
        $user_sessions{$user_id}->{current_conversation} = $data->{conversation_id};
        $c->send(encode_json({ type => 'joined_conversation', conversation_id => $data->{conversation_id} }));
    }
    elsif ($type eq 'leave_conversation') {
        $user_sessions{$user_id}->{current_conversation} = undef;
        $c->send(encode_json({ type => 'left_conversation' }));
    }
    elsif ($type eq 'typing') {
        broadcast_typing($user_id, $data->{conversation_id}, $data->{is_typing});
    }
    elsif ($type eq 'ping') {
        $c->send(encode_json({ type => 'pong' }));
    }
}

# Функции для работы с WebSocket
sub broadcast_message {
    my ($conversation_id, $message_data) = @_;
    
    # Получаем участников чата
    my $db = app->db;
    my $participants = $db->selectall_arrayref(
        'SELECT user_id FROM conversation_participants WHERE conversation_id = ?',
        { Slice => {} }, $conversation_id
    );
    
    # Отправляем сообщение всем подключенным участникам
    for my $participant (@$participants) {
        my $user_id = $participant->{user_id};
        if (exists $websocket_connections{$user_id}) {
            $websocket_connections{$user_id}->send(encode_json({
                type => 'new_message',
                conversation_id => $conversation_id,
                message => $message_data
            }));
        }
    }
}

sub broadcast_user_status {
    my ($user_id, $status) = @_;
    
    # Отправляем статус всем подключенным пользователям
    for my $ws_user_id (keys %websocket_connections) {
        next if $ws_user_id == $user_id; # Не отправляем себе
        
        if (exists $websocket_connections{$ws_user_id}) {
            $websocket_connections{$ws_user_id}->send(encode_json({
                type => 'user_status',
                user_id => $user_id,
                username => $user_sessions{$user_id}->{username},
                status => $status
            }));
        }
    }
}

sub broadcast_typing {
    my ($user_id, $conversation_id, $is_typing) = @_;
    
    # Получаем участников чата
    my $db = app->db;
    my $participants = $db->selectall_arrayref(
        'SELECT user_id FROM conversation_participants WHERE conversation_id = ? AND user_id != ?',
        { Slice => {} }, $conversation_id, $user_id
    );
    
    # Отправляем статус печати
    for my $participant (@$participants) {
        my $participant_id = $participant->{user_id};
        if (exists $websocket_connections{$participant_id}) {
            $websocket_connections{$participant_id}->send(encode_json({
                type => 'typing',
                conversation_id => $conversation_id,
                user_id => $user_id,
                username => $user_sessions{$user_id}->{username},
                is_typing => $is_typing
            }));
        }
    }
}

# Скачивание файлов
get '/download/:guid' => sub {
    my $c = shift;
    my $guid = $c->param('guid');
    my $db = $c->db;
    
    # Находим файл по GUID
    my $file = $db->selectrow_hashref(
        'SELECT * FROM files WHERE stored_name = ?', 
        undef, $guid
    );
    
    unless ($file) {
        return $c->render(text => 'File not found', status => 404);
    }
    
    my $file_path = File::Spec->catfile('files', $file->{stored_name});
    
    unless (-f $file_path) {
        return $c->render(text => 'File not found on disk', status => 404);
    }
    
    # Получаем реальный размер файла
    my $real_size = -s $file_path;
    
    # Устанавливаем заголовки с правильной кодировкой
    $c->res->headers->content_type($file->{mime_type} || 'application/octet-stream');
    $c->res->headers->content_disposition("attachment; filename*=UTF-8''" . uri_escape_utf8($file->{original_name}));
    $c->res->headers->content_length($real_size);
    
    # Читаем файл в память и отправляем
    open my $fh, '<:raw', $file_path or do {
        return $c->render(text => 'Cannot read file', status => 500);
    };
    
    my $buffer;
    my $content = '';
    while (read($fh, $buffer, 8192)) {
        $content .= $buffer;
    }
    close $fh;
    
    $c->render(data => $content);
};

# Страница логина
get '/login' => sub {
    my $c = shift;
    $c->render(template => 'login');
};

# Обработчик формы логина
post '/login' => sub {
    my $c = shift;
    my $username = $c->param('username');
    my $password = $c->param('password');
    
    my $user = authenticate_user($c, $username, $password);
    if ($user) {
        $c->session(user_id => $user->{id});
        $c->redirect_to('/');
    } else {
        $c->stash(error => 'Неверные учетные данные');
        $c->render(template => 'login');
    }
};

# Страница регистрации
get '/register' => sub {
    my $c = shift;
    $c->render(template => 'register');
};

# Обработчик формы регистрации
post '/register' => sub {
    my $c = shift;
    my $username = $c->param('username');
    my $password = $c->param('password');
    my $email = $c->param('email') || '';
    
    my $db = $c->db;
    
    # Проверяем, не существует ли уже такой пользователь
    my $existing_user = $db->selectrow_hashref(
        'SELECT id FROM users WHERE username = ?', 
        undef, $username
    );
    
    if ($existing_user) {
        $c->stash(error => 'Пользователь с таким именем уже существует');
        $c->render(template => 'register');
        return;
    }
    
    # Создаем нового пользователя
    eval {
        $db->do(
            'INSERT INTO users (username, password_hash, email, created_at, status) VALUES (?, ?, ?, ?, ?)',
            undef, $username, $password, $email, time(), 'offline'
        );
        
        # Логиним пользователя сразу после регистрации
        my $user = $db->selectrow_hashref(
            'SELECT * FROM users WHERE username = ?', 
            undef, $username
        );
        
        if ($user) {
            $c->session(user_id => $user->{id});
            $c->redirect_to('/');
        } else {
            $c->redirect_to('/login');
        }
    };
    
    if ($@) {
        $c->stash(error => 'Ошибка при создании пользователя: ' . $@);
        $c->render(template => 'register');
    }
};

app->start;
