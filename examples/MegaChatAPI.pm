package MegaChatAPI;
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Carp;

=head1 NAME

MegaChatAPI - Вспомогательный модуль для работы с MegaChat API

=head1 DESCRIPTION

Удобная Perl библиотека для взаимодействия с REST API MegaChat приложения.
Предоставляет высокоуровневые методы для всех основных операций.

=head1 SYNOPSIS

    use MegaChatAPI;
    
    my $api = MegaChatAPI->new(
        base_url => 'http://localhost:3000',
        username => 'admin',
        password => 'admin'
    );
    
    # Авторизация
    my $user = $api->login();
    
    # Работа с чатами
    my $chats = $api->get_conversations();
    my $new_chat = $api->create_conversation("Test Chat", "Description");
    
    # Отправка сообщений
    $api->send_message($chat_id, "Hello World!");
    
    # Получение сообщений
    my $messages = $api->get_messages($chat_id);

=cut

our $VERSION = '1.0.0';

# === КОНСТРУКТОР И ИНИЦИАЛИЗАЦИЯ ===

sub new {
    my ($class, %args) = @_;
    
    my $self = {
        base_url => $args{base_url} || 'http://localhost:3000',
        username => $args{username} || '',
        password => $args{password} || '',
        timeout  => $args{timeout} || 30,
        debug    => $args{debug} || 0,
        
        # Внутренние объекты
        ua => undef,
        json => undef,
        logged_in => 0,
        user_info => undef,
        last_error => undef
    };
    
    bless $self, $class;
    
    # Инициализация HTTP клиента
    $self->{ua} = LWP::UserAgent->new(
        timeout => $self->{timeout},
        agent => "MegaChatAPI-Perl/$VERSION",
        cookie_jar => HTTP::Cookies->new()
    );
    
    # Инициализация JSON парсера
    $self->{json} = JSON->new->utf8;
    
    return $self;
}

# === ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ===

sub _debug {
    my ($self, $message) = @_;
    
    if ($self->{debug}) {
        print STDERR "[MegaChatAPI DEBUG] $message\n";
    }
}

sub _error {
    my ($self, $error) = @_;
    
    $self->{last_error} = $error;
    $self->_debug("ERROR: $error");
    
    return undef;
}

sub get_last_error {
    my ($self) = @_;
    return $self->{last_error};
}

sub _request {
    my ($self, $method, $endpoint, $data) = @_;
    
    my $url = $self->{base_url} . $endpoint;
    $self->_debug("$method $url");
    
    my $req;
    
    if ($method eq 'GET') {
        $req = HTTP::Request->new('GET', $url);
    } elsif ($method eq 'POST') {
        $req = HTTP::Request->new('POST', $url);
        
        if ($endpoint =~ m{/(login|register)$}) {
            # Форма для авторизации/регистрации
            $req->header('Content-Type' => 'application/x-www-form-urlencoded');
            $req->content($data) if $data;
        } else {
            # JSON для API
            $req->header('Content-Type' => 'application/json');
            $req->content($self->{json}->encode($data)) if $data;
        }
    } elsif ($method eq 'PUT') {
        $req = HTTP::Request->new('PUT', $url);
        $req->header('Content-Type' => 'application/json');
        $req->content($self->{json}->encode($data)) if $data;
    } elsif ($method eq 'DELETE') {
        $req = HTTP::Request->new('DELETE', $url);
    } else {
        return $self->_error("Неподдерживаемый HTTP метод: $method");
    }
    
    my $response = $self->{ua}->request($req);
    
    if ($response->is_success || $response->code == 302) {
        $self->_debug("Response: " . $response->code);
        
        # Обработка JSON ответов
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $result = eval { $self->{json}->decode($response->content) };
            if ($@) {
                return $self->_error("Ошибка парсинга JSON: $@");
            }
            return $result;
        } else {
            # Для редиректов и HTML страниц
            return {
                success => 1,
                content => $response->content,
                headers => $response->headers,
                redirect => $response->header('Location')
            };
        }
    } else {
        my $error = "HTTP Error: " . $response->status_line;
        
        # Пытаемся получить детали ошибки из JSON
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $error_data = eval { $self->{json}->decode($response->content) };
            if ($error_data && $error_data->{message}) {
                $error .= " - " . $error_data->{message};
            }
        }
        
        return $self->_error($error);
    }
}

# === АВТОРИЗАЦИЯ ===

sub login {
    my ($self, $username, $password) = @_;
    
    $username //= $self->{username};
    $password //= $self->{password};
    
    if (!$username || !$password) {
        return $self->_error("Не указаны учетные данные для входа");
    }
    
    $self->_debug("Попытка авторизации пользователя: $username");
    
    # Сначала проверяем не авторизованы ли уже
    my $check_result = $self->check_auth();
    if ($check_result && $check_result->{success}) {
        $self->{logged_in} = 1;
        $self->{user_info} = $check_result->{user};
        $self->_debug("Уже авторизован как: " . $check_result->{user}->{username});
        return $check_result->{user};
    }
    
    # Выполняем авторизацию
    my $login_data = "username=$username&password=$password";
    my $result = $self->_request('POST', '/login', $login_data);
    
    if ($result && ($result->{success} || $result->{redirect})) {
        # Проверяем статус авторизации
        my $auth_check = $self->check_auth();
        if ($auth_check && $auth_check->{success}) {
            $self->{logged_in} = 1;
            $self->{user_info} = $auth_check->{user};
            $self->_debug("Авторизация успешна: " . $auth_check->{user}->{username});
            return $auth_check->{user};
        }
    }
    
    return $self->_error("Ошибка авторизации");
}

sub register {
    my ($self, $username, $email, $password) = @_;
    
    if (!$username || !$email || !$password) {
        return $self->_error("Не указаны обязательные поля для регистрации");
    }
    
    $self->_debug("Регистрация пользователя: $username");
    
    my $register_data = "username=$username&email=$email&password=$password&confirm_password=$password";
    my $result = $self->_request('POST', '/register', $register_data);
    
    if ($result && ($result->{success} || $result->{redirect})) {
        return { success => 1, username => $username };
    }
    
    return $self->_error("Ошибка регистрации");
}

sub check_auth {
    my ($self) = @_;
    
    return $self->_request('GET', '/api/auth/check');
}

sub logout {
    my ($self) = @_;
    
    my $result = $self->_request('POST', '/api/auth/logout');
    
    if ($result && ($result->{success} || $result->{redirect})) {
        $self->{logged_in} = 0;
        $self->{user_info} = undef;
        return { success => 1 };
    }
    
    return $self->_error("Ошибка выхода из системы");
}

sub is_logged_in {
    my ($self) = @_;
    return $self->{logged_in};
}

sub get_user_info {
    my ($self) = @_;
    return $self->{user_info};
}

# === РАБОТА С ЧАТАМИ ===

sub get_conversations {
    my ($self) = @_;
    
    my $result = $self->_request('GET', '/api/conversations');
    
    if ($result && ref($result) eq 'ARRAY') {
        return $result;
    }
    
    return $self->_error("Ошибка получения списка чатов");
}

sub get_conversation {
    my ($self, $conversation_id) = @_;
    
    if (!$conversation_id) {
        return $self->_error("Не указан ID чата");
    }
    
    return $self->_request('GET', "/api/conversations/$conversation_id");
}

sub create_conversation {
    my ($self, $name, $description, $participants) = @_;
    
    if (!$name) {
        return $self->_error("Не указано название чата");
    }
    
    my $data = {
        name => $name,
        description => $description || '',
        participants => $participants || []
    };
    
    return $self->_request('POST', '/api/conversations', $data);
}

sub update_conversation {
    my ($self, $conversation_id, $name, $description) = @_;
    
    if (!$conversation_id) {
        return $self->_error("Не указан ID чата");
    }
    
    my $data = {};
    $data->{name} = $name if defined $name;
    $data->{description} = $description if defined $description;
    
    return $self->_request('PUT', "/api/conversations/$conversation_id", $data);
}

sub delete_conversation {
    my ($self, $conversation_id) = @_;
    
    if (!$conversation_id) {
        return $self->_error("Не указан ID чата");
    }
    
    return $self->_request('DELETE', "/api/conversations/$conversation_id");
}

# === РАБОТА С СООБЩЕНИЯМИ ===

sub get_messages {
    my ($self, $conversation_id, $limit, $offset) = @_;
    
    if (!$conversation_id) {
        return $self->_error("Не указан ID чата");
    }
    
    my $endpoint = "/api/conversations/$conversation_id/messages";
    
    # Добавляем параметры пагинации если указаны
    my @params;
    push @params, "limit=$limit" if $limit;
    push @params, "offset=$offset" if $offset;
    
    if (@params) {
        $endpoint .= '?' . join('&', @params);
    }
    
    my $result = $self->_request('GET', $endpoint);
    
    if ($result && ref($result) eq 'ARRAY') {
        return $result;
    }
    
    return $self->_error("Ошибка получения сообщений");
}

sub send_message {
    my ($self, $conversation_id, $content, $message_type) = @_;
    
    if (!$conversation_id || !$content) {
        return $self->_error("Не указаны обязательные параметры сообщения");
    }
    
    my $data = {
        conversation_id => $conversation_id,
        content => $content,
        message_type => $message_type || 'text'
    };
    
    return $self->_request('POST', '/api/messages', $data);
}

sub search_messages {
    my ($self, $query, $conversation_id) = @_;
    
    if (!$query) {
        return $self->_error("Не указан поисковый запрос");
    }
    
    my $endpoint = "/api/messages/search?q=" . $query;
    $endpoint .= "&conversation_id=$conversation_id" if $conversation_id;
    
    my $result = $self->_request('GET', $endpoint);
    
    if ($result && ref($result) eq 'ARRAY') {
        return $result;
    }
    
    return $self->_error("Ошибка поиска сообщений");
}

sub update_message {
    my ($self, $message_id, $content) = @_;
    
    if (!$message_id || !$content) {
        return $self->_error("Не указаны обязательные параметры для обновления");
    }
    
    my $data = { content => $content };
    
    return $self->_request('PUT', "/api/messages/$message_id", $data);
}

sub delete_message {
    my ($self, $message_id) = @_;
    
    if (!$message_id) {
        return $self->_error("Не указан ID сообщения");
    }
    
    return $self->_request('DELETE', "/api/messages/$message_id");
}

# === РАБОТА С ЗАМЕТКАМИ ===

sub get_notes {
    my ($self) = @_;
    
    my $result = $self->_request('GET', '/api/notes');
    
    if ($result && ref($result) eq 'ARRAY') {
        return $result;
    }
    
    return $self->_error("Ошибка получения заметок");
}

sub get_note {
    my ($self, $note_id) = @_;
    
    if (!$note_id) {
        return $self->_error("Не указан ID заметки");
    }
    
    return $self->_request('GET', "/api/notes/$note_id");
}

sub create_note {
    my ($self, $title, $content, $tags) = @_;
    
    if (!$title || !$content) {
        return $self->_error("Не указаны обязательные поля заметки");
    }
    
    my $data = {
        title => $title,
        content => $content,
        tags => $tags || []
    };
    
    return $self->_request('POST', '/api/notes', $data);
}

sub update_note {
    my ($self, $note_id, $title, $content, $tags) = @_;
    
    if (!$note_id) {
        return $self->_error("Не указан ID заметки");
    }
    
    my $data = {};
    $data->{title} = $title if defined $title;
    $data->{content} = $content if defined $content;
    $data->{tags} = $tags if defined $tags;
    
    return $self->_request('PUT', "/api/notes/$note_id", $data);
}

sub delete_note {
    my ($self, $note_id) = @_;
    
    if (!$note_id) {
        return $self->_error("Не указан ID заметки");
    }
    
    return $self->_request('DELETE', "/api/notes/$note_id");
}

# === РАБОТА С ПОЛЬЗОВАТЕЛЯМИ ===

sub search_users {
    my ($self, $query) = @_;
    
    my $endpoint = '/api/users/search';
    $endpoint .= "?q=$query" if $query;
    
    my $result = $self->_request('GET', $endpoint);
    
    if ($result && ref($result) eq 'ARRAY') {
        return $result;
    }
    
    return $self->_error("Ошибка поиска пользователей");
}

# === ВЫСОКОУРОВНЕВЫЕ МЕТОДЫ ===

sub send_text_message {
    my ($self, $conversation_id, $text) = @_;
    return $self->send_message($conversation_id, $text, 'text');
}

sub send_file_message {
    my ($self, $conversation_id, $file_path, $file_name) = @_;
    
    # Пока что простая заглушка - полная реализация требует multipart загрузки
    return $self->_error("Загрузка файлов через API пока не реализована");
}

sub get_recent_messages {
    my ($self, $conversation_id, $count) = @_;
    
    $count ||= 10;
    return $self->get_messages($conversation_id, $count);
}

sub get_chat_participants {
    my ($self, $conversation_id) = @_;
    
    my $chat = $self->get_conversation($conversation_id);
    
    if ($chat && $chat->{participants}) {
        return $chat->{participants};
    }
    
    return [];
}

sub create_simple_chat {
    my ($self, $name) = @_;
    
    return $self->create_conversation($name, "Создан через API", []);
}

# === УТИЛИТАРНЫЕ МЕТОДЫ ===

sub format_message {
    my ($self, $message) = @_;
    
    return unless ref($message) eq 'HASH';
    
    my $time = $message->{created_at} || 'неизвестно';
    my $user = $message->{username} || "User #" . ($message->{sender_id} || '?');
    my $content = $message->{content} || '[нет содержимого]';
    my $type = $message->{message_type} || 'text';
    
    return "[$time] $user ($type): $content";
}

sub get_stats {
    my ($self) = @_;
    
    my $stats = {
        logged_in => $self->{logged_in},
        user => $self->{user_info},
        last_error => $self->{last_error}
    };
    
    if ($self->{logged_in}) {
        # Получаем базовую статистику
        my $chats = $self->get_conversations();
        $stats->{total_chats} = $chats ? scalar(@$chats) : 0;
        
        my $notes = $self->get_notes();
        $stats->{total_notes} = $notes ? scalar(@$notes) : 0;
        
        my $users = $self->search_users('');
        $stats->{total_users} = $users ? scalar(@$users) : 0;
    }
    
    return $stats;
}

1;

__END__

=head1 МЕТОДЫ

=head2 Конструктор

=head3 new(%args)

Создает новый экземпляр MegaChatAPI.

Параметры:
- base_url: URL сервера MegaChat (по умолчанию http://localhost:3000)
- username: Имя пользователя для автоматической авторизации
- password: Пароль для автоматической авторизации  
- timeout: Таймаут HTTP запросов в секундах (по умолчанию 30)
- debug: Включить отладочный вывод (по умолчанию 0)

=head2 Авторизация

=head3 login($username, $password)

Авторизация в системе. Возвращает информацию о пользователе при успехе.

=head3 register($username, $email, $password)

Регистрация нового пользователя.

=head3 check_auth()

Проверка текущего статуса авторизации.

=head3 logout()

Выход из системы.

=head3 is_logged_in()

Проверяет авторизован ли пользователь.

=head3 get_user_info()

Возвращает информацию о текущем пользователе.

=head2 Чаты

=head3 get_conversations()

Получение списка всех чатов.

=head3 get_conversation($id)

Получение детальной информации о чате.

=head3 create_conversation($name, $description, $participants)

Создание нового чата.

=head3 update_conversation($id, $name, $description)

Обновление информации о чате.

=head3 delete_conversation($id)

Удаление чата.

=head2 Сообщения

=head3 get_messages($conversation_id, $limit, $offset)

Получение сообщений из чата с поддержкой пагинации.

=head3 send_message($conversation_id, $content, $type)

Отправка сообщения в чат.

=head3 search_messages($query, $conversation_id)

Поиск сообщений по содержимому.

=head3 update_message($message_id, $content)

Редактирование сообщения.

=head3 delete_message($message_id)

Удаление сообщения.

=head2 Заметки

=head3 get_notes()

Получение всех заметок пользователя.

=head3 get_note($id)

Получение конкретной заметки.

=head3 create_note($title, $content, $tags)

Создание новой заметки.

=head3 update_note($id, $title, $content, $tags)

Обновление заметки.

=head3 delete_note($id)

Удаление заметки.

=head2 Пользователи

=head3 search_users($query)

Поиск пользователей по имени или email.

=head2 Вспомогательные методы

=head3 get_last_error()

Возвращает текст последней ошибки.

=head3 format_message($message)

Форматирует сообщение для вывода.

=head3 get_stats()

Возвращает базовую статистику текущей сессии.

=head1 ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ

    # Создание клиента и авторизация
    my $api = MegaChatAPI->new(
        base_url => 'http://localhost:3000',
        debug => 1
    );
    
    my $user = $api->login('admin', 'admin');
    die "Ошибка авторизации: " . $api->get_last_error() unless $user;
    
    # Создание чата и отправка сообщения
    my $chat = $api->create_conversation("API Test Chat");
    my $chat_id = $chat->{id};
    
    $api->send_message($chat_id, "Привет из API!");
    
    # Получение и вывод сообщений
    my $messages = $api->get_messages($chat_id);
    foreach my $msg (@$messages) {
        print $api->format_message($msg) . "\n";
    }
    
    # Создание заметки
    $api->create_note(
        "API Заметка",
        "Содержание заметки созданной через API",
        ['api', 'test']
    );
    
    # Поиск пользователей
    my $users = $api->search_users('admin');
    print "Найдено пользователей: " . scalar(@$users) . "\n";

=head1 ОБРАБОТКА ОШИБОК

Все методы возвращают undef при ошибке. Детали ошибки можно получить 
через метод get_last_error().

    my $result = $api->send_message($chat_id, "text");
    if (!$result) {
        print "Ошибка: " . $api->get_last_error() . "\n";
    }

=head1 ТРЕБОВАНИЯ

- Perl 5.10+
- LWP::UserAgent
- HTTP::Request
- HTTP::Cookies  
- JSON
- Carp

=head1 АВТОР

MegaChat API Examples

=head1 ЛИЦЕНЗИЯ

Учебный проект. Свободное использование в образовательных целях.

=cut
