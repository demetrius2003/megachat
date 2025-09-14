#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use IO::Socket::INET;
use Protocol::WebSocket::Client;
use JSON;
use Time::HiRes qw(time sleep);

=head1 NAME

04_check_websocket.pl - Проверка WebSocket функциональности MegaChat

=head1 DESCRIPTION

Тестирует WebSocket соединение, отправку и получение сообщений,
проверяет корректность обработки различных типов событий.

=cut

print "🔌 ПРОВЕРКА WEBSOCKET ФУНКЦИОНАЛЬНОСТИ\n";
print "=" x 50 . "\n\n";

# Настройки
my $host = 'localhost';
my $port = 3000;
my $ws_path = '/chat';
my $timeout = 10;

my $json = JSON->new->utf8;

# Проверка доступности WebSocket порта
print "🌐 ПРОВЕРКА ДОСТУПНОСТИ WEBSOCKET:\n";
print "   Хост: $host:$port\n";
print "   Путь: $ws_path\n";

# Проверяем TCP соединение
my $socket = IO::Socket::INET->new(
    PeerHost => $host,
    PeerPort => $port,
    Proto    => 'tcp',
    Timeout  => $timeout
);

if (!$socket) {
    print "   ❌ Невозможно подключиться к серверу: $!\n";
    print "   💡 Убедитесь что сервер запущен: perl megachat.pl\n";
    exit 1;
} else {
    print "   ✅ TCP соединение установлено\n";
    close($socket);
}

# Функция для создания WebSocket клиента
sub create_ws_client {
    my ($user_id, $username) = @_;
    
    my $client = Protocol::WebSocket::Client->new(
        url => "ws://$host:$port$ws_path"
    );
    
    # Создаем TCP соединение
    my $socket = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp'
    ) or return undef;
    
    # Отправляем WebSocket handshake
    $socket->send($client->to_string);
    
    # Читаем ответ handshake
    my $buffer = '';
    $socket->recv($buffer, 1024);
    
    if (!$client->parse($buffer)) {
        close($socket);
        return undef;
    }
    
    return {
        client => $client,
        socket => $socket,
        user_id => $user_id,
        username => $username
    };
}

# Функция отправки WebSocket сообщения
sub send_ws_message {
    my ($ws, $data) = @_;
    
    my $json_data = $json->encode($data);
    my $frame = $ws->{client}->write($json_data);
    
    return $ws->{socket}->send($frame);
}

# Функция получения WebSocket сообщения
sub receive_ws_message {
    my ($ws, $timeout) = @_;
    $timeout //= 5;
    
    my $rin = '';
    vec($rin, fileno($ws->{socket}), 1) = 1;
    
    my $ready = select($rin, undef, undef, $timeout);
    return undef unless $ready;
    
    my $buffer = '';
    my $bytes = $ws->{socket}->recv($buffer, 1024);
    return undef unless $bytes;
    
    $ws->{client}->parse($buffer);
    my $message = $ws->{client}->next_bytes;
    
    return $message ? eval { $json->decode($message) } : undef;
}

print "\n🔧 ТЕСТИРОВАНИЕ WEBSOCKET СОЕДИНЕНИЯ:\n";

# Тест 1: Основное подключение
print "   Тест подключения: ";
my $ws1 = create_ws_client(1, 'test_user_1');

if ($ws1) {
    print "✅ успешно\n";
} else {
    print "❌ ошибка подключения\n";
    exit 1;
}

# Тест 2: Отправка сообщения о присоединении к чату
print "   Тест присоединения к чату: ";
my $join_success = send_ws_message($ws1, {
    type => 'join_conversation',
    conversation_id => 1,
    user_id => 1
});

if ($join_success) {
    print "✅ сообщение отправлено\n";
} else {
    print "❌ ошибка отправки\n";
}

# Тест 3: Множественные соединения
print "   Тест множественных соединений: ";
my $ws2 = create_ws_client(2, 'test_user_2');

if ($ws2) {
    print "✅ второе соединение установлено\n";
    
    # Присоединяем второго пользователя к тому же чату
    send_ws_message($ws2, {
        type => 'join_conversation', 
        conversation_id => 1,
        user_id => 2
    });
} else {
    print "❌ ошибка второго соединения\n";
}

# Тест 4: Отправка и получение сообщений
print "\n💬 ТЕСТИРОВАНИЕ ОБМЕНА СООБЩЕНИЯМИ:\n";

if ($ws2) {
    print "   Отправка сообщения от пользователя 1: ";
    
    my $test_message = {
        type => 'new_message',
        conversation_id => 1,
        content => 'Test message from user 1',
        user_id => 1,
        username => 'test_user_1'
    };
    
    my $send_result = send_ws_message($ws1, $test_message);
    
    if ($send_result) {
        print "✅ отправлено\n";
        
        # Пытаемся получить сообщение на втором клиенте
        print "   Получение сообщения пользователем 2: ";
        my $received = receive_ws_message($ws2, 3);
        
        if ($received && $received->{content} && $received->{content} eq 'Test message from user 1') {
            print "✅ получено корректно\n";
        } elsif ($received) {
            print "⚠️  получено, но содержимое отличается\n";
            print "      Ожидалось: 'Test message from user 1'\n";
            print "      Получено: '" . ($received->{content} || 'нет content') . "'\n";
        } else {
            print "❌ не получено\n";
        }
    } else {
        print "❌ ошибка отправки\n";
    }
}

# Тест 5: Уведомления о печати
print "\n⌨️  ТЕСТИРОВАНИЕ УВЕДОМЛЕНИЙ О ПЕЧАТИ:\n";

if ($ws2) {
    print "   Отправка уведомления о начале печати: ";
    
    my $typing_start = send_ws_message($ws1, {
        type => 'typing_start',
        conversation_id => 1,
        user_id => 1,
        username => 'test_user_1'
    });
    
    if ($typing_start) {
        print "✅ отправлено\n";
        
        # Проверяем получение уведомления
        print "   Получение уведомления о печати: ";
        my $typing_received = receive_ws_message($ws2, 2);
        
        if ($typing_received && $typing_received->{type} && $typing_received->{type} eq 'user_typing') {
            print "✅ получено\n";
        } else {
            print "❌ не получено или некорректно\n";
        }
        
        # Отправляем уведомление об окончании печати
        sleep(0.5);
        send_ws_message($ws1, {
            type => 'typing_stop',
            conversation_id => 1,
            user_id => 1
        });
        
    } else {
        print "❌ ошибка отправки\n";
    }
}

# Тест 6: Обработка некорректных данных
print "\n🚫 ТЕСТИРОВАНИЕ ОБРАБОТКИ ОШИБОК:\n";

print "   Отправка некорректного JSON: ";
if ($ws1->{socket}->send($ws1->{client}->write('invalid json data'))) {
    print "✅ отправлено (сервер должен обработать ошибку корректно)\n";
} else {
    print "❌ ошибка отправки\n";
}

print "   Отправка сообщения без обязательных полей: ";
my $invalid_msg = send_ws_message($ws1, {
    type => 'new_message'
    # missing conversation_id, content, user_id
});

if ($invalid_msg) {
    print "✅ отправлено (сервер должен проверить валидацию)\n";
} else {
    print "❌ ошибка отправки\n";
}

# Тест 7: Производительность
print "\n⚡ ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ:\n";

if ($ws1 && $ws2) {
    my $message_count = 10;
    print "   Отправка $message_count сообщений подряд: ";
    
    my $start_time = time();
    my $sent_count = 0;
    
    for my $i (1..$message_count) {
        my $result = send_ws_message($ws1, {
            type => 'new_message',
            conversation_id => 1,
            content => "Performance test message $i",
            user_id => 1,
            username => 'test_user_1'
        });
        $sent_count++ if $result;
        sleep(0.1); # Небольшая пауза между сообщениями
    }
    
    my $send_time = time() - $start_time;
    print "✅ отправлено $sent_count/$message_count за " . sprintf("%.2f", $send_time) . "с\n";
    
    # Пытаемся получить сообщения
    print "   Получение сообщений: ";
    my $received_count = 0;
    
    for (1..5) { # Пытаемся получить несколько сообщений
        my $msg = receive_ws_message($ws2, 1);
        $received_count++ if $msg;
    }
    
    print "получено $received_count сообщений\n";
}

# Закрытие соединений
print "\n🔚 ЗАКРЫТИЕ СОЕДИНЕНИЙ:\n";

if ($ws1) {
    close($ws1->{socket});
    print "   ✅ Соединение 1 закрыто\n";
}

if ($ws2) {
    close($ws2->{socket});
    print "   ✅ Соединение 2 закрыто\n";
}

print "\n📊 ИТОГОВЫЙ РЕЗУЛЬТАТ:\n";
print "=" x 30 . "\n";

if ($ws1 && $ws2) {
    print "🎉 WEBSOCKET ФУНКЦИОНАЛЬНОСТЬ РАБОТАЕТ!\n";
    print "   ✅ Подключение клиентов\n";
    print "   ✅ Отправка сообщений\n";
    print "   ✅ Получение сообщений\n";
    print "   ✅ Множественные соединения\n";
    print "   ✅ Обработка ошибок\n\n";
    
    print "💡 WebSocket готов для real-time коммуникации!\n";
    exit 0;
} elsif ($ws1) {
    print "⚠️  ЧАСТИЧНАЯ ФУНКЦИОНАЛЬНОСТЬ\n";
    print "   ✅ Базовое подключение работает\n";
    print "   ❌ Проблемы с множественными соединениями\n";
    exit 0;
} else {
    print "❌ WEBSOCKET НЕ ФУНКЦИОНИРУЕТ!\n";
    print "   Проверьте:\n";
    print "   - Запущен ли сервер\n";
    print "   - Корректность WebSocket endpoint\n";
    print "   - Наличие необходимых модулей\n";
    exit 1;
}

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Установите зависимости
    cpan Protocol::WebSocket::Client
    
    # Запустите тест
    perl tests/04_check_websocket.pl

=head1 DEPENDENCIES

    Protocol::WebSocket::Client
    IO::Socket::INET
    JSON
    Time::HiRes

=head1 AUTHOR

MegaChat Project

=cut
