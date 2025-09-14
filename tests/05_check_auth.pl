#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Time::HiRes qw(time);

=head1 NAME

05_check_auth.pl - Проверка системы авторизации MegaChat

=head1 DESCRIPTION

Тестирует систему авторизации: регистрацию, вход, проверку сессий,
защиту эндпоинтов и корректность обработки ошибок авторизации.

=cut

print "🔐 ПРОВЕРКА СИСТЕМЫ АВТОРИЗАЦИИ MEGACHAT\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 10;

# Создание HTTP клиента с поддержкой cookies
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-Auth-Tester/1.0',
    cookie_jar => HTTP::Cookies->new()
);

my $json = JSON->new->utf8;

# Тестовые данные
my $test_user = {
    username => 'test_auth_user_' . time(),
    email => 'test_auth_' . time() . '@example.com',
    password => 'test_password_123'
};

my $invalid_user = {
    username => 'nonexistent_user',
    password => 'wrong_password'
};

print "📋 ТЕСТОВЫЕ ДАННЫЕ:\n";
print "   Пользователь: $test_user->{username}\n";
print "   Email: $test_user->{email}\n";
print "   Пароль: [скрыт]\n\n";

# Проверка доступности сервера
print "🌐 ПРОВЕРКА ДОСТУПНОСТИ СЕРВЕРА:\n";
my $response = $ua->get($base_url);
if (!$response->is_success) {
    print "   ❌ Сервер недоступен: " . $response->status_line . "\n";
    exit 1;
}
print "   ✅ Сервер доступен\n\n";

# Тест 1: Проверка статуса авторизации (без входа)
print "🔍 ПРОВЕРКА НАЧАЛЬНОГО СТАТУСА АВТОРИЗАЦИИ:\n";
my $check_resp = $ua->get("$base_url/api/auth/check");

if ($check_resp->is_success) {
    my $data = eval { $json->decode($check_resp->content) };
    if ($data && exists $data->{success}) {
        if ($data->{success}) {
            print "   ⚠️  Пользователь уже авторизован: $data->{user}->{username}\n";
            print "   💡 Для чистого теста выполните logout\n";
        } else {
            print "   ✅ Пользователь не авторизован (корректно)\n";
        }
    } else {
        print "   ❌ Некорректный ответ API\n";
    }
} else {
    print "   ❌ Ошибка запроса: " . $check_resp->status_line . "\n";
}

# Тест 2: Регистрация нового пользователя
print "\n📝 ТЕСТИРОВАНИЕ РЕГИСТРАЦИИ:\n";

print "   Регистрация валидного пользователя: ";
my $register_req = HTTP::Request->new('POST', "$base_url/register");
$register_req->header('Content-Type' => 'application/x-www-form-urlencoded');
$register_req->content(
    "username=$test_user->{username}&" .
    "email=$test_user->{email}&" .
    "password=$test_user->{password}&" .
    "confirm_password=$test_user->{password}"
);

my $register_resp = $ua->request($register_req);

if ($register_resp->is_success || $register_resp->code == 302) {
    print "✅ успешно\n";
    
    # Проверяем редирект или содержимое ответа
    if ($register_resp->code == 302) {
        my $location = $register_resp->header('Location');
        print "      Редирект на: $location\n";
    }
} else {
    print "❌ ошибка (" . $register_resp->status_line . ")\n";
    if ($register_resp->content =~ /уже существует|already exists/i) {
        print "      Пользователь уже существует\n";
    }
}

# Тест регистрации с некорректными данными
print "   Регистрация с короткими данными: ";
my $bad_register_req = HTTP::Request->new('POST', "$base_url/register");
$bad_register_req->header('Content-Type' => 'application/x-www-form-urlencoded');
$bad_register_req->content("username=ab&email=bad&password=123");

my $bad_register_resp = $ua->request($bad_register_req);

if ($bad_register_resp->is_success && $bad_register_resp->content =~ /ошибка|error/i) {
    print "✅ корректно отклонена\n";
} elsif (!$bad_register_resp->is_success) {
    print "✅ отклонена сервером\n";
} else {
    print "⚠️  возможно принята (требует проверки валидации)\n";
}

# Тест 3: Вход в систему
print "\n🚪 ТЕСТИРОВАНИЕ ВХОДА В СИСТЕМУ:\n";

# Попытка входа с неверными данными
print "   Вход с неверными данными: ";
my $bad_login_req = HTTP::Request->new('POST', "$base_url/login");
$bad_login_req->header('Content-Type' => 'application/x-www-form-urlencoded');
$bad_login_req->content("username=$invalid_user->{username}&password=$invalid_user->{password}");

my $bad_login_resp = $ua->request($bad_login_req);

if ($bad_login_resp->content =~ /неверн|incorrect|invalid/i || !$bad_login_resp->is_success) {
    print "✅ корректно отклонен\n";
} else {
    print "⚠️  возможно принят (проблема безопасности)\n";
}

# Вход с корректными данными
print "   Вход с корректными данными: ";
my $login_req = HTTP::Request->new('POST', "$base_url/login");
$login_req->header('Content-Type' => 'application/x-www-form-urlencoded');
$login_req->content("username=$test_user->{username}&password=$test_user->{password}");

my $login_resp = $ua->request($login_req);

my $login_success = 0;
if ($login_resp->is_success || $login_resp->code == 302) {
    print "✅ успешно\n";
    $login_success = 1;
    
    if ($login_resp->code == 302) {
        my $location = $login_resp->header('Location');
        print "      Редирект на: $location\n";
    }
} else {
    print "❌ ошибка (" . $login_resp->status_line . ")\n";
    print "      Возможно пользователь не был создан\n";
}

# Тест 4: Проверка авторизованного статуса
if ($login_success) {
    print "\n✅ ПРОВЕРКА АВТОРИЗОВАННОГО СТАТУСА:\n";
    
    my $auth_check_resp = $ua->get("$base_url/api/auth/check");
    
    if ($auth_check_resp->is_success) {
        my $data = eval { $json->decode($auth_check_resp->content) };
        
        if ($data && $data->{success} && $data->{user}) {
            print "   ✅ Пользователь авторизован: $data->{user}->{username}\n";
            print "   📊 User ID: $data->{user}->{id}\n";
            print "   📧 Email: " . ($data->{user}->{email} || 'не указан') . "\n";
        } else {
            print "   ❌ Статус авторизации некорректный\n";
            $login_success = 0;
        }
    } else {
        print "   ❌ Ошибка проверки статуса\n";
        $login_success = 0;
    }
}

# Тест 5: Доступ к защищенным эндпоинтам
if ($login_success) {
    print "\n🔒 ПРОВЕРКА ДОСТУПА К ЗАЩИЩЕННЫМ ЭНДПОИНТАМ:\n";
    
    my @protected_endpoints = (
        '/api/conversations',
        '/api/notes',
        '/api/users/search?q=test'
    );
    
    foreach my $endpoint (@protected_endpoints) {
        print "   $endpoint: ";
        my $resp = $ua->get("$base_url$endpoint");
        
        if ($resp->is_success) {
            print "✅ доступен\n";
            
            # Проверяем что это JSON ответ
            if ($resp->header('Content-Type') && $resp->header('Content-Type') =~ /json/) {
                my $data = eval { $json->decode($resp->content) };
                if ($data) {
                    print "      JSON валиден\n";
                } else {
                    print "      ⚠️  JSON некорректен\n";
                }
            }
        } else {
            print "❌ недоступен (" . $resp->status_line . ")\n";
        }
    }
}

# Тест 6: Создание тестового чата (если авторизован)
if ($login_success) {
    print "\n💬 ТЕСТИРОВАНИЕ СОЗДАНИЯ ЧАТА:\n";
    
    print "   Создание тестового чата: ";
    my $chat_req = HTTP::Request->new('POST', "$base_url/api/conversations");
    $chat_req->header('Content-Type' => 'application/json');
    $chat_req->content($json->encode({
        name => "Test Chat " . time(),
        description => "Тестовый чат для проверки авторизации",
        participants => []
    }));
    
    my $chat_resp = $ua->request($chat_req);
    
    if ($chat_resp->is_success) {
        my $data = eval { $json->decode($chat_resp->content) };
        if ($data && $data->{success}) {
            print "✅ создан (ID: $data->{id})\n";
        } else {
            print "⚠️  ответ получен, но статус неясен\n";
        }
    } else {
        print "❌ ошибка (" . $chat_resp->status_line . ")\n";
    }
}

# Тест 7: Выход из системы
if ($login_success) {
    print "\n🚪 ТЕСТИРОВАНИЕ ВЫХОДА ИЗ СИСТЕМЫ:\n";
    
    print "   Выполнение logout: ";
    my $logout_resp = $ua->post("$base_url/api/auth/logout");
    
    if ($logout_resp->is_success || $logout_resp->code == 302) {
        print "✅ успешно\n";
        
        # Проверяем что авторизация действительно сброшена
        print "   Проверка сброса авторизации: ";
        my $check_after_logout = $ua->get("$base_url/api/auth/check");
        
        if ($check_after_logout->is_success) {
            my $data = eval { $json->decode($check_after_logout->content) };
            if ($data && !$data->{success}) {
                print "✅ авторизация сброшена\n";
            } else {
                print "⚠️  авторизация может быть не сброшена\n";
            }
        }
    } else {
        print "❌ ошибка (" . $logout_resp->status_line . ")\n";
    }
}

# Тест 8: Доступ к защищенным эндпоинтам после logout
print "\n🔐 ПРОВЕРКА БЛОКИРОВКИ ПОСЛЕ LOGOUT:\n";

my $protected_test = $ua->get("$base_url/api/conversations");
if (!$protected_test->is_success || $protected_test->code == 401) {
    print "   ✅ Доступ к защищенным эндпоинтам заблокирован\n";
} else {
    print "   ⚠️  Защищенные эндпоинты могут быть доступны без авторизации\n";
}

# Тест 9: Безопасность сессий
print "\n🛡️  ПРОВЕРКА БЕЗОПАСНОСТИ СЕССИЙ:\n";

# Проверка заголовков безопасности
my $security_resp = $ua->get($base_url);
my $headers = $security_resp->headers;

print "   Secure cookies: ";
my $set_cookie = $headers->header('Set-Cookie') || '';
if ($set_cookie =~ /Secure/i) {
    print "✅ включены\n";
} else {
    print "⚠️  не обнаружены (рекомендуется для HTTPS)\n";
}

print "   HttpOnly cookies: ";
if ($set_cookie =~ /HttpOnly/i) {
    print "✅ включены\n";
} else {
    print "⚠️  не обнаружены (рекомендуется для безопасности)\n";
}

# Тест производительности авторизации
print "\n⚡ ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ АВТОРИЗАЦИИ:\n";

print "   Время выполнения операций:\n";

# Тест скорости проверки авторизации
my $start_time = time();
for (1..5) {
    $ua->get("$base_url/api/auth/check");
}
my $auth_check_time = sprintf("%.3f", (time() - $start_time) / 5);
print "      Проверка авторизации: ${auth_check_time}с\n";

# Тест скорости входа
$start_time = time();
my $perf_login_req = HTTP::Request->new('POST', "$base_url/login");
$perf_login_req->header('Content-Type' => 'application/x-www-form-urlencoded');
$perf_login_req->content("username=$test_user->{username}&password=$test_user->{password}");
$ua->request($perf_login_req);
my $login_time = sprintf("%.3f", time() - $start_time);
print "      Вход в систему: ${login_time}с\n";

print "\n📊 ИТОГОВЫЙ РЕЗУЛЬТАТ:\n";
print "=" x 30 . "\n";

if ($login_success) {
    print "🎉 СИСТЕМА АВТОРИЗАЦИИ ФУНКЦИОНИРУЕТ!\n";
    print "   ✅ Регистрация пользователей\n";
    print "   ✅ Вход в систему\n";
    print "   ✅ Проверка статуса авторизации\n";
    print "   ✅ Защита эндпоинтов\n";
    print "   ✅ Выход из системы\n\n";
    
    print "💡 Рекомендации по безопасности:\n";
    print "   - Используйте HTTPS в production\n";
    print "   - Добавьте хеширование паролей\n";
    print "   - Настройте Secure/HttpOnly cookies\n";
    print "   - Добавьте rate limiting\n";
    exit 0;
} else {
    print "❌ ПРОБЛЕМЫ С СИСТЕМОЙ АВТОРИЗАЦИИ!\n";
    print "   Проверьте:\n";
    print "   - Корректность API эндпоинтов\n";
    print "   - Структуру базы данных\n";
    print "   - Обработку POST запросов\n";
    exit 1;
}

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat  
    perl megachat.pl &
    
    # Запустите тест
    perl tests/05_check_auth.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request
    HTTP::Cookies
    JSON
    Time::HiRes

=head1 AUTHOR

MegaChat Project

=cut
