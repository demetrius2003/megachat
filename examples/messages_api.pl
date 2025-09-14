#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Time::HiRes qw(time sleep);
use POSIX qw(strftime);
use Encode qw(encode_utf8);

=head1 NAME

messages_api.pl - Работа с сообщениями через MegaChat API

=head1 DESCRIPTION

Демонстрирует отправку, получение, поиск и управление сообщениями
через REST API MegaChat приложения. Включает различные типы сообщений
и интеграцию с чатами.

=cut

# Включаем UTF-8 вывод
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "💬 MEGACHAT API - РАБОТА С СООБЩЕНИЯМИ\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 30;

# HTTP клиент с поддержкой cookies
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-Messages-Example/1.0',
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
    
    # Проверяем авторизацию
    my $check_result = api_request('GET', '/api/auth/check');
    if ($check_result && $check_result->{success}) {
        print "   ✅ Уже авторизован как: $check_result->{user}->{username}\n\n";
        return $check_result->{user};
    }
    
    # Авторизация
    my $login_req = HTTP::Request->new('POST', "$base_url/login");
    $login_req->header('Content-Type' => 'application/x-www-form-urlencoded');
    $login_req->content("username=$username&password=$password");
    
    my $login_resp = $ua->request($login_req);
    
    if ($login_resp->is_success || $login_resp->code == 302) {
        print "   ✅ Авторизация успешна\n";
        
        my $auth_check = api_request('GET', '/api/auth/check');
        if ($auth_check && $auth_check->{success}) {
            print "   👤 Вошли как: $auth_check->{user}->{username} (ID: $auth_check->{user}->{id})\n\n";
            return $auth_check->{user};
        }
    }
    
    print "   ❌ Ошибка авторизации\n\n";
    return undef;
}

sub print_message_info {
    my ($message, $prefix) = @_;
    $prefix //= '';
    
    if (ref($message) eq 'HASH') {
        my $time_str = $message->{created_at} || 'неизвестно';
        my $username = $message->{username} || "User #" . ($message->{sender_id} || '?');
        my $type = $message->{message_type} || 'text';
        
        print "${prefix}💬 [$time_str] $username ($type):\n";
        
        if ($type eq 'text') {
            my $content = $message->{content} || '';
            # Обрезаем длинные сообщения
            if (length($content) > 100) {
                $content = substr($content, 0, 100) . '...';
            }
            print "${prefix}   📝 \"$content\"\n";
        } elsif ($type eq 'file') {
            print "${prefix}   📎 Файл: " . ($message->{file_name} || 'неизвестно') . "\n";
            print "${prefix}   💾 Размер: " . ($message->{file_size} || '?') . " байт\n";
        } elsif ($type eq 'voice') {
            print "${prefix}   🎤 Голосовое сообщение\n";
            print "${prefix}   ⏱️  Длительность: " . ($message->{duration} || '?') . " сек\n";
        }
        
        if ($message->{id}) {
            print "${prefix}   🆔 ID: $message->{id}\n";
        }
    }
}

sub generate_test_messages {
    return [
        {
            content => "Привет! Это тестовое сообщение от API клиента.",
            message_type => "text"
        },
        {
            content => "Проверяем UTF-8 поддержку: 🚀 💬 📝 🎉\nМногострочное сообщение\nс эмодзи и спецсимволами: @#\$%",
            message_type => "text"
        },
        {
            content => "# Markdown тест\n\n**Жирный текст**\n*Курсив*\n\n- Список\n- Элементов\n\n```perl\nprint \"Hello World\";\n```\n\n> Цитата из сообщения",
            message_type => "text"
        },
        {
            content => "Длинное сообщение для проверки обработки большого объема текста. " . 
                      "Это сообщение содержит много повторяющегося текста. " x 10,
            message_type => "text"
        },
        {
            content => "🎯 Тестирование различных случаев:\n" .
                      "• Обычный текст\n" .
                      "• Числа: 123456789\n" .
                      "• Спецсимволы: !@#\$%^&*()\n" .
                      "• URL: https://example.com\n" .
                      "• Email: test@example.com\n" .
                      "• Хештеги: #megachat #api #test",
            message_type => "text"
        }
    ];
}

sub send_message {
    my ($conversation_id, $message_data) = @_;
    
    my $full_data = {
        conversation_id => $conversation_id,
        %$message_data
    };
    
    return api_request('POST', '/api/messages', $full_data);
}

sub get_conversation_messages {
    my ($conversation_id) = @_;
    
    return api_request('GET', "/api/conversations/$conversation_id/messages");
}

sub search_messages {
    my ($query, $conversation_id) = @_;
    
    my $endpoint = '/api/messages/search?q=' . $query;
    $endpoint .= "&conversation_id=$conversation_id" if $conversation_id;
    
    return api_request('GET', $endpoint);
}

# === ОСНОВНАЯ ПРОГРАММА ===

# Проверка сервера
print "🌐 ПРОВЕРКА ДОСТУПНОСТИ API:\n";
my $server_check = api_request('GET', '/');
if (!$server_check || $server_check->{error}) {
    print "❌ Сервер недоступен! Убедитесь что MegaChat запущен.\n";
    exit 1;
}
print "\n";

# Авторизация
my $user = login_user('admin', 'admin');
if (!$user) {
    print "❌ Не удалось авторизоваться. Проверьте учетные данные.\n";
    exit 1;
}

# Получение чатов для отправки сообщений
print "📋 ПОЛУЧЕНИЕ СПИСКА ЧАТОВ:\n";
my $chats = api_request('GET', '/api/conversations');
my $target_chat_id;

if ($chats && ref($chats) eq 'ARRAY' && @$chats) {
    # Выбираем первый доступный чат
    $target_chat_id = $chats->[0]->{id};
    print "   ✅ Выбран чат: '$chats->[0]->{name}' (ID: $target_chat_id)\n";
    print "   📊 Всего доступных чатов: " . scalar(@$chats) . "\n";
} else {
    print "   ⚠️  Чаты не найдены, создаем тестовый чат...\n";
    
    my $new_chat = api_request('POST', '/api/conversations', {
        name => "Messages API Test Chat " . time(),
        description => "Чат для тестирования сообщений через API",
        participants => []
    });
    
    if ($new_chat && $new_chat->{success}) {
        $target_chat_id = $new_chat->{id};
        print "   ✅ Создан тестовый чат (ID: $target_chat_id)\n";
    } else {
        print "   ❌ Не удалось создать чат для тестирования\n";
        exit 1;
    }
}
print "\n";

# === ОТПРАВКА СООБЩЕНИЙ ===

print "📤 ОТПРАВКА РАЗЛИЧНЫХ ТИПОВ СООБЩЕНИЙ:\n";

my $test_messages = generate_test_messages();
my @sent_messages;

foreach my $i (0..$#$test_messages) {
    my $msg_data = $test_messages->[$i];
    my $msg_num = $i + 1;
    
    print "   $msg_num️⃣ Отправка сообщения типа '$msg_data->{message_type}':\n";
    
    # Показываем превью содержимого
    my $preview = substr($msg_data->{content}, 0, 50);
    $preview .= '...' if length($msg_data->{content}) > 50;
    print "      📝 Превью: \"$preview\"\n";
    
    my $result = send_message($target_chat_id, $msg_data);
    
    if ($result && $result->{success}) {
        push @sent_messages, { %$result, original => $msg_data };
        print "      ✅ Сообщение отправлено (ID: $result->{id})\n";
    } else {
        print "      ❌ Ошибка отправки сообщения\n";
        if ($result && $result->{error}) {
            print "      📋 Детали: $result->{error}\n";
        }
    }
    
    # Небольшая пауза между сообщениями
    sleep(0.5);
    print "\n";
}

# === ПОЛУЧЕНИЕ СООБЩЕНИЙ ===

print "📥 ПОЛУЧЕНИЕ СООБЩЕНИЙ ИЗ ЧАТА:\n";

my $messages = get_conversation_messages($target_chat_id);

if ($messages && ref($messages) eq 'ARRAY') {
    print "   📊 Всего сообщений в чате: " . scalar(@$messages) . "\n";
    print "   📤 Отправлено в этой сессии: " . scalar(@sent_messages) . "\n\n";
    
    # Показываем последние сообщения
    my @recent_messages = reverse @$messages; # Новые сверху
    my $show_count = 10;
    
    print "   📋 Последние " . min($show_count, scalar(@recent_messages)) . " сообщений:\n\n";
    
    foreach my $i (0..min($show_count-1, $#recent_messages)) {
        my $msg = $recent_messages[$i];
        print_message_info($msg, "      ");
        print "\n";
    }
} else {
    print "   ❌ Ошибка получения сообщений\n\n";
}

# === ПОИСК СООБЩЕНИЙ ===

print "🔍 ПОИСК СООБЩЕНИЙ:\n";

my @search_queries = (
    'тест',
    'API',
    'Привет',
    'эмодзи',
    'markdown',
    'megachat'
);

foreach my $query (@search_queries) {
    print "   🔎 Поиск '$query':\n";
    
    # Поиск по всем чатам
    my $global_search = search_messages($query);
    
    if ($global_search && ref($global_search) eq 'ARRAY') {
        print "      🌐 Глобальный поиск: " . scalar(@$global_search) . " сообщений\n";
        
        foreach my $result (@$global_search) {
            my $chat_info = $result->{conversation_name} ? " в '$result->{conversation_name}'" : '';
            print "         💬 " . ($result->{username} || 'Неизвестно') . "$chat_info\n";
        }
    } else {
        print "      🌐 Глобальный поиск: не найдено\n";
    }
    
    # Поиск в конкретном чате
    my $chat_search = search_messages($query, $target_chat_id);
    
    if ($chat_search && ref($chat_search) eq 'ARRAY') {
        print "      📁 В текущем чате: " . scalar(@$chat_search) . " сообщений\n";
    } else {
        print "      📁 В текущем чате: не найдено\n";
    }
    
    print "\n";
}

# === АНАЛИЗ СООБЩЕНИЙ ===

print "📊 АНАЛИЗ СООБЩЕНИЙ:\n";

if ($messages && ref($messages) eq 'ARRAY') {
    my %stats = (
        total => scalar(@$messages),
        by_type => {},
        by_user => {},
        total_chars => 0,
        with_emoji => 0,
        with_links => 0
    );
    
    # Анализируем каждое сообщение
    foreach my $msg (@$messages) {
        # Статистика по типам
        my $type = $msg->{message_type} || 'unknown';
        $stats{by_type}->{$type}++;
        
        # Статистика по пользователям
        my $user = $msg->{username} || "User#" . ($msg->{sender_id} || 'unknown');
        $stats{by_user}->{$user}++;
        
        # Анализ содержимого
        if ($msg->{content}) {
            $stats{total_chars} += length($msg->{content});
            
            # Поиск эмодзи (простая проверка на Unicode символы)
            if ($msg->{content} =~ /[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{1F1E0}-\x{1F1FF}]/) {
                $stats{with_emoji}++;
            }
            
            # Поиск ссылок
            if ($msg->{content} =~ /https?:\/\/|www\./i) {
                $stats{with_links}++;
            }
        }
    }
    
    print "   📈 Общая статистика:\n";
    print "      💬 Всего сообщений: $stats{total}\n";
    print "      📝 Общий объем текста: $stats{total_chars} символов\n";
    
    if ($stats{total} > 0) {
        my $avg_chars = int($stats{total_chars} / $stats{total});
        print "      📊 Средняя длина сообщения: $avg_chars символов\n";
    }
    
    print "      😀 Сообщений с эмодзи: $stats{with_emoji}\n";
    print "      🔗 Сообщений со ссылками: $stats{with_links}\n";
    
    print "\n   📋 Статистика по типам сообщений:\n";
    foreach my $type (sort keys %{$stats{by_type}}) {
        my $count = $stats{by_type}->{$type};
        my $percent = $stats{total} > 0 ? sprintf("%.1f", ($count/$stats{total})*100) : 0;
        print "      🏷️  $type: $count ($percent%)\n";
    }
    
    print "\n   👥 Статистика по пользователям:\n";
    my @top_users = sort { $stats{by_user}->{$b} <=> $stats{by_user}->{$a} } keys %{$stats{by_user}};
    
    foreach my $user (@top_users[0..min(4, $#top_users)]) { # Топ 5 пользователей
        my $count = $stats{by_user}->{$user};
        my $percent = $stats{total} > 0 ? sprintf("%.1f", ($count/$stats{total})*100) : 0;
        print "      👤 $user: $count сообщений ($percent%)\n";
    }
}

print "\n";

# === ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ ===

print "🔧 ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ:\n";

# Отправка сообщения с упоминанием
print "   📢 Отправка сообщения с упоминанием:\n";
my $mention_msg = {
    content => "\@admin Это тестовое сообщение с упоминанием пользователя!",
    message_type => "text"
};

my $mention_result = send_message($target_chat_id, $mention_msg);
if ($mention_result && $mention_result->{success}) {
    print "      ✅ Сообщение с упоминанием отправлено\n";
} else {
    print "      ❌ Ошибка отправки упоминания\n";
}

# Отправка сообщения с форматированием
print "\n   🎨 Отправка форматированного сообщения:\n";
my $formatted_msg = {
    content => "**API тестирование завершено!**\n\n" .
              "_Результаты:_\n" .
              "- ✅ Отправка сообщений\n" .
              "- ✅ Получение сообщений\n" .
              "- ✅ Поиск по содержимому\n" .
              "- ✅ Анализ статистики\n\n" .
              "`Время завершения: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "`",
    message_type => "text"
};

my $formatted_result = send_message($target_chat_id, $formatted_msg);
if ($formatted_result && $formatted_result->{success}) {
    print "      ✅ Форматированное сообщение отправлено\n";
} else {
    print "      ❌ Ошибка отправки форматированного сообщения\n";
}

# Проверка реакций (если поддерживается)
print "\n   ❤️  Тестирование реакций на сообщения:\n";
if (@sent_messages) {
    my $msg_for_reaction = $sent_messages[0];
    print "      💬 Пробуем добавить реакцию к сообщению ID: $msg_for_reaction->{id}\n";
    
    # Эмуляция добавления реакции (может быть не реализовано)
    my $reaction_data = {
        message_id => $msg_for_reaction->{id},
        emoji => "👍"
    };
    
    my $reaction_result = api_request('POST', '/api/reactions', $reaction_data);
    if ($reaction_result && $reaction_result->{success}) {
        print "      ✅ Реакция добавлена\n";
    } else {
        print "      💡 API реакций может быть не реализован\n";
    }
} else {
    print "      ⚠️  Нет отправленных сообщений для тестирования реакций\n";
}

print "\n";

# === ИТОГОВАЯ СТАТИСТИКА ===

print "📊 ИТОГОВАЯ СТАТИСТИКА СЕССИИ:\n";
print "=" x 40 . "\n";

# Получаем финальный список сообщений
my $final_messages = get_conversation_messages($target_chat_id);

if ($final_messages && ref($final_messages) eq 'ARRAY') {
    my $total_final = scalar(@$final_messages);
    my $sent_count = scalar(@sent_messages);
    
    print "   📈 Результаты:\n";
    print "      💬 Всего сообщений в чате: $total_final\n";
    print "      📤 Отправлено в этой сессии: $sent_count\n";
    print "      🎯 Целевой чат ID: $target_chat_id\n";
    
    # Показываем сообщения отправленные в этой сессии
    if (@sent_messages) {
        print "\n   📋 Отправленные сообщения:\n";
        foreach my $sent (@sent_messages) {
            my $preview = substr($sent->{original}->{content}, 0, 30);
            $preview .= '...' if length($sent->{original}->{content}) > 30;
            print "      💬 ID $sent->{id}: \"$preview\"\n";
        }
    }
}

print "\n💡 РЕКОМЕНДАЦИИ ДЛЯ РАЗРАБОТКИ:\n";
print "   ✏️  Реализуйте редактирование сообщений\n";
print "   🗑️  Добавьте удаление сообщений\n";
print "   ❤️  Расширьте систему реакций\n";
print "   📎 Улучшите поддержку вложений\n";
print "   🔍 Добавьте продвинутый поиск (регулярные выражения)\n";
print "   📊 Реализуйте пагинацию для больших чатов\n";
print "   📢 Добавьте систему уведомлений\n";
print "   🔒 Реализуйте права доступа к сообщениям\n";
print "   📈 Добавьте детальную аналитику сообщений\n";

print "\n🎉 ДЕМОНСТРАЦИЯ РАБОТЫ С СООБЩЕНИЯМИ ЗАВЕРШЕНА!\n";

# Вспомогательная функция
sub min {
    my ($a, $b) = @_;
    return $a < $b ? $a : $b;
}

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите пример
    perl examples/messages_api.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request
    HTTP::Cookies
    JSON
    Time::HiRes
    POSIX
    Encode

=head1 AUTHOR

MegaChat API Examples

=cut
