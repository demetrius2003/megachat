#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Data::Dumper;

=head1 NAME

chat_crud.pl - CRUD операции с чатами через MegaChat API

=head1 DESCRIPTION

Демонстрирует полный набор операций Create, Read, Update, Delete
для работы с чатами через REST API MegaChat приложения.

=cut

# Включаем UTF-8 вывод
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "💬 MEGACHAT API - CRUD ОПЕРАЦИИ С ЧАТАМИ\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 30;

# HTTP клиент с поддержкой cookies для сессий
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-API-Example/1.0',
    cookie_jar => HTTP::Cookies->new()
);

my $json = JSON->new->utf8->pretty;

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

sub api_request {
    my ($method, $endpoint, $data) = @_;
    
    my $url = $base_url . $endpoint;
    my $req;
    
    if ($method eq 'GET') {
        $req = HTTP::Request->new('GET', $url);
    } elsif ($method eq 'POST') {
        $req = HTTP::Request->new('POST', $url);
        $req->header('Content-Type' => 'application/json');
        $req->content($json->encode($data)) if $data;
    } elsif ($method eq 'PUT') {
        $req = HTTP::Request->new('PUT', $url);
        $req->header('Content-Type' => 'application/json');
        $req->content($json->encode($data)) if $data;
    } elsif ($method eq 'DELETE') {
        $req = HTTP::Request->new('DELETE', $url);
    }
    
    my $response = $ua->request($req);
    
    print "   📡 $method $endpoint: ";
    if ($response->is_success) {
        print "✅ " . $response->code . "\n";
        
        # Парсим JSON ответ если есть
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $result = eval { $json->decode($response->content) };
            if ($result) {
                return $result;
            } else {
                print "      ⚠️  Некорректный JSON в ответе\n";
                return { error => 'Invalid JSON', content => $response->content };
            }
        } else {
            return { success => 1, content => $response->content };
        }
    } else {
        print "❌ " . $response->status_line . "\n";
        return { error => $response->status_line, code => $response->code };
    }
}

sub login_user {
    my ($username, $password) = @_;
    
    print "🔐 АВТОРИЗАЦИЯ ПОЛЬЗОВАТЕЛЯ:\n";
    print "   Пользователь: $username\n";
    
    # Сначала проверяем не авторизованы ли уже
    my $check_result = api_request('GET', '/api/auth/check');
    if ($check_result && $check_result->{success}) {
        print "   ✅ Уже авторизован как: $check_result->{user}->{username}\n\n";
        return $check_result->{user};
    }
    
    # Выполняем авторизацию через форму
    my $login_req = HTTP::Request->new('POST', "$base_url/login");
    $login_req->header('Content-Type' => 'application/x-www-form-urlencoded');
    $login_req->content("username=$username&password=$password");
    
    my $login_resp = $ua->request($login_req);
    
    if ($login_resp->is_success || $login_resp->code == 302) {
        print "   ✅ Авторизация успешна\n";
        
        # Проверяем статус после авторизации
        my $auth_check = api_request('GET', '/api/auth/check');
        if ($auth_check && $auth_check->{success}) {
            print "   👤 Вошли как: $auth_check->{user}->{username} (ID: $auth_check->{user}->{id})\n\n";
            return $auth_check->{user};
        }
    }
    
    print "   ❌ Ошибка авторизации\n\n";
    return undef;
}

sub print_chat_info {
    my ($chat, $prefix) = @_;
    $prefix //= '';
    
    if (ref($chat) eq 'HASH') {
        print "${prefix}📋 Чат #$chat->{id}: '$chat->{name}'\n";
        print "${prefix}   Описание: " . ($chat->{description} || 'нет') . "\n";
        print "${prefix}   Создан: " . ($chat->{created_at} || 'неизвестно') . "\n";
        print "${prefix}   Создатель: " . ($chat->{created_by} || 'неизвестно') . "\n";
        
        if ($chat->{participants} && ref($chat->{participants}) eq 'ARRAY') {
            print "${prefix}   Участники (" . scalar(@{$chat->{participants}}) . "): ";
            print join(', ', map { $_->{username} || $_->{id} } @{$chat->{participants}}) . "\n";
        }
    }
}

# === ОСНОВНАЯ ПРОГРАММА ===

# Проверка доступности сервера
print "🌐 ПРОВЕРКА ДОСТУПНОСТИ API:\n";
my $server_check = api_request('GET', '/');
if (!$server_check || $server_check->{error}) {
    print "❌ Сервер недоступен! Убедитесь что MegaChat запущен.\n";
    print "💡 Запуск: cd megachat && perl megachat.pl\n";
    exit 1;
}
print "\n";

# Авторизация (используем тестового пользователя)
my $user = login_user('admin', 'admin');
if (!$user) {
    print "❌ Не удалось авторизоваться. Создайте пользователя 'admin' или измените данные в скрипте.\n";
    exit 1;
}

# === CREATE - СОЗДАНИЕ ЧАТОВ ===

print "➕ CREATE - СОЗДАНИЕ НОВЫХ ЧАТОВ:\n";

my @new_chats;

# Создание простого чата
print "   1️⃣ Создание простого чата:\n";
my $simple_chat_data = {
    name => "API Demo Chat " . time(),
    description => "Демонстрационный чат созданный через API",
    participants => []
};

my $simple_chat = api_request('POST', '/api/conversations', $simple_chat_data);
if ($simple_chat && $simple_chat->{success}) {
    push @new_chats, $simple_chat;
    print "      ✅ Создан чат ID: $simple_chat->{id}\n";
} else {
    print "      ❌ Ошибка создания чата\n";
}

# Создание чата с участниками
print "   2️⃣ Создание чата с участниками:\n";

# Сначала найдем доступных пользователей
my $users_search = api_request('GET', '/api/users/search?q=user');
my @available_users;

if ($users_search && ref($users_search) eq 'ARRAY') {
    @available_users = grep { $_->{id} != $user->{id} } @$users_search; # Исключаем себя
    print "      🔍 Найдено пользователей: " . scalar(@available_users) . "\n";
}

my $group_chat_data = {
    name => "API Group Chat " . time(),
    description => "Групповой чат с участниками",
    participants => [map { { id => $_->{id}, username => $_->{username} } } @available_users[0..1]] # Берем первых двух
};

my $group_chat = api_request('POST', '/api/conversations', $group_chat_data);
if ($group_chat && $group_chat->{success}) {
    push @new_chats, $group_chat;
    print "      ✅ Создан групповой чат ID: $group_chat->{id}\n";
} else {
    print "      ❌ Ошибка создания группового чата\n";
}

print "\n";

# === READ - ЧТЕНИЕ СПИСКА ЧАТОВ ===

print "📖 READ - ПОЛУЧЕНИЕ СПИСКА ЧАТОВ:\n";

my $all_chats = api_request('GET', '/api/conversations');
if ($all_chats && ref($all_chats) eq 'ARRAY') {
    print "   📋 Всего чатов: " . scalar(@$all_chats) . "\n\n";
    
    foreach my $chat (@$all_chats) {
        print_chat_info($chat, "   ");
        print "\n";
    }
} else {
    print "   ❌ Ошибка получения списка чатов\n\n";
}

# === READ - ПОЛУЧЕНИЕ ДЕТАЛЬНОЙ ИНФОРМАЦИИ О ЧАТЕ ===

if (@new_chats) {
    print "🔍 READ - ПОЛУЧЕНИЕ ДЕТАЛЬНОЙ ИНФОРМАЦИИ О ЧАТЕ:\n";
    
    my $chat_id = $new_chats[0]->{id};
    print "   Получаем информацию о чате #$chat_id:\n";
    
    my $chat_details = api_request('GET', "/api/conversations/$chat_id");
    if ($chat_details && !$chat_details->{error}) {
        print "   ✅ Детальная информация получена:\n";
        print_chat_info($chat_details, "      ");
        
        # Получаем сообщения чата
        print "\n   📨 Сообщения чата:\n";
        my $messages = api_request('GET', "/api/conversations/$chat_id/messages");
        if ($messages && ref($messages) eq 'ARRAY') {
            if (@$messages) {
                foreach my $msg (@$messages) {
                    print "      💬 [$msg->{created_at}] $msg->{username}: $msg->{content}\n";
                }
            } else {
                print "      📭 Сообщений пока нет\n";
            }
        }
    } else {
        print "   ❌ Ошибка получения детальной информации\n";
    }
    print "\n";
}

# === UPDATE - ОБНОВЛЕНИЕ ЧАТОВ ===

print "✏️  UPDATE - ОБНОВЛЕНИЕ ЧАТОВ:\n";
print "   ⚠️  Примечание: В текущей версии API UPDATE операции могут быть не реализованы\n";

if (@new_chats) {
    my $chat_id = $new_chats[0]->{id};
    print "   Попытка обновления чата #$chat_id:\n";
    
    my $update_data = {
        name => "Updated API Demo Chat",
        description => "Обновленное описание через API"
    };
    
    # Пробуем PUT запрос
    my $update_result = api_request('PUT', "/api/conversations/$chat_id", $update_data);
    if ($update_result && !$update_result->{error}) {
        print "      ✅ Чат обновлен\n";
    } else {
        print "      ℹ️  UPDATE операция не поддерживается (код: " . ($update_result->{code} || 'unknown') . ")\n";
    }
}
print "\n";

# === DELETE - УДАЛЕНИЕ ЧАТОВ ===

print "🗑️  DELETE - УДАЛЕНИЕ ЧАТОВ:\n";
print "   ⚠️  Примечание: В текущей версии API DELETE операции могут быть не реализованы\n";

if (@new_chats) {
    # Удаляем только один чат для демонстрации
    my $chat_to_delete = pop @new_chats;
    my $chat_id = $chat_to_delete->{id};
    
    print "   Попытка удаления чата #$chat_id:\n";
    
    my $delete_result = api_request('DELETE', "/api/conversations/$chat_id");
    if ($delete_result && !$delete_result->{error}) {
        print "      ✅ Чат удален\n";
    } else {
        print "      ℹ️  DELETE операция не поддерживается (код: " . ($delete_result->{code} || 'unknown') . ")\n";
    }
    
    # Проверяем что чат действительно удален
    print "   Проверка удаления:\n";
    my $check_deleted = api_request('GET', "/api/conversations/$chat_id");
    if ($check_deleted && $check_deleted->{error}) {
        print "      ✅ Чат действительно удален (404)\n";
    } else {
        print "      ℹ️  Чат все еще доступен\n";
    }
}
print "\n";

# === ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ ===

print "🔧 ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ:\n";

# Поиск чатов
print "   🔍 Поиск чатов по имени:\n";
my $search_result = api_request('GET', '/api/conversations');
if ($search_result && ref($search_result) eq 'ARRAY') {
    my @api_chats = grep { $_->{name} && $_->{name} =~ /API/i } @$search_result;
    print "      📋 Найдено чатов с 'API' в названии: " . scalar(@api_chats) . "\n";
    foreach my $chat (@api_chats) {
        print "         📝 $chat->{name} (ID: $chat->{id})\n";
    }
}

# Отправка сообщения в чат
if (@new_chats) {
    my $chat_id = $new_chats[0]->{id};
    print "\n   💬 Отправка тестового сообщения в чат #$chat_id:\n";
    
    my $message_data = {
        conversation_id => $chat_id,
        content => "Привет! Это тестовое сообщение отправленное через API.",
        message_type => "text"
    };
    
    my $message_result = api_request('POST', '/api/messages', $message_data);
    if ($message_result && $message_result->{success}) {
        print "      ✅ Сообщение отправлено (ID: $message_result->{id})\n";
    } else {
        print "      ❌ Ошибка отправки сообщения\n";
    }
}

print "\n";

# === ИТОГОВАЯ СТАТИСТИКА ===

print "📊 ИТОГОВАЯ СТАТИСТИКА:\n";
print "=" x 30 . "\n";

# Получаем финальный список чатов
my $final_chats = api_request('GET', '/api/conversations');
if ($final_chats && ref($final_chats) eq 'ARRAY') {
    my $total_chats = scalar(@$final_chats);
    my @my_chats = grep { $_->{created_by} && $_->{created_by} == $user->{id} } @$final_chats;
    my $my_chats_count = scalar(@my_chats);
    
    print "   📈 Всего чатов в системе: $total_chats\n";
    print "   👤 Ваших чатов: $my_chats_count\n";
    print "   ➕ Создано в этой сессии: " . scalar(@new_chats) . "\n";
    
    if (@my_chats) {
        print "\n   📋 Ваши чаты:\n";
        foreach my $chat (@my_chats) {
            print "      💬 $chat->{name} (ID: $chat->{id})\n";
        }
    }
}

print "\n💡 РЕКОМЕНДАЦИИ ДЛЯ РАЗРАБОТКИ:\n";
print "   🔧 Реализуйте PUT/PATCH для обновления чатов\n";
print "   🗑️  Реализуйте DELETE для удаления чатов\n";
print "   👥 Добавьте API для управления участниками\n";
print "   🔍 Добавьте фильтрацию и поиск по чатам\n";
print "   📊 Добавьте пагинацию для больших списков\n";

print "\n🎉 ДЕМОНСТРАЦИЯ CRUD ОПЕРАЦИЙ ЗАВЕРШЕНА!\n";

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите пример
    perl examples/chat_crud.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request  
    HTTP::Cookies
    JSON
    Data::Dumper

=head1 AUTHOR

MegaChat API Examples

=cut
