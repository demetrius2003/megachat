#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Time::HiRes qw(time);
use POSIX qw(strftime);

=head1 NAME

auth_users.pl - Управление авторизацией и пользователями через MegaChat API

=head1 DESCRIPTION

Демонстрирует операции авторизации, регистрации, управления пользователями
и проверки безопасности через REST API MegaChat приложения.

=cut

# Включаем UTF-8 вывод
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "👥 MEGACHAT API - АВТОРИЗАЦИЯ И УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ\n";
print "=" x 60 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 30;

# HTTP клиент БЕЗ общих cookies (для тестирования разных сессий)
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-Auth-Example/1.0'
);

my $json = JSON->new->utf8->pretty;

# === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ===

sub api_request {
    my ($method, $endpoint, $data, $ua_instance) = @_;
    $ua_instance //= $ua;
    
    my $url = $base_url . $endpoint;
    my $req;
    
    if ($method eq 'GET') {
        $req = HTTP::Request->new('GET', $url);
    } elsif ($method eq 'POST') {
        $req = HTTP::Request->new('POST', $url);
        if ($endpoint =~ m{/(login|register)$}) {
            # Форма для авторизации/регистрации
            $req->header('Content-Type' => 'application/x-www-form-urlencoded');
            $req->content($data);
        } else {
            # JSON для API
            $req->header('Content-Type' => 'application/json');
            $req->content($json->encode($data)) if $data;
        }
    }
    
    my $response = $ua_instance->request($req);
    
    print "   📡 $method $endpoint: ";
    if ($response->is_success || $response->code == 302) {
        print "✅ " . $response->code;
        if ($response->code == 302) {
            my $location = $response->header('Location') || '';
            print " → $location";
        }
        print "\n";
        
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $result = eval { $json->decode($response->content) };
            if ($result) {
                return $result;
            } else {
                return { success => 1, content => $response->content };
            }
        } else {
            return { 
                success => 1, 
                content => $response->content, 
                headers => $response->headers,
                redirect => $response->header('Location')
            };
        }
    } else {
        print "❌ " . $response->status_line . "\n";
        
        # Пытаемся получить JSON ошибку
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $error_data = eval { $json->decode($response->content) };
            if ($error_data) {
                return { error => $response->status_line, code => $response->code, details => $error_data };
            }
        }
        
        return { error => $response->status_line, code => $response->code };
    }
}

sub create_user_session {
    my $cookies = HTTP::Cookies->new();
    return LWP::UserAgent->new(
        timeout => $timeout,
        agent => 'MegaChat-Session/1.0',
        cookie_jar => $cookies
    );
}

sub generate_test_users {
    my $timestamp = int(time());
    
    return [
        {
            username => "test_user_$timestamp",
            email => "test$timestamp\@megachat.demo",
            password => "secure_password_123",
            role => "user"
        },
        {
            username => "demo_admin_$timestamp",
            email => "admin$timestamp\@megachat.demo", 
            password => "admin_secure_456",
            role => "admin"
        },
        {
            username => "guest_$timestamp",
            email => "guest$timestamp\@megachat.demo",
            password => "guest_pass_789",
            role => "guest"
        }
    ];
}

sub print_user_info {
    my ($user, $prefix) = @_;
    $prefix //= '';
    
    if (ref($user) eq 'HASH') {
        print "${prefix}👤 Пользователь: $user->{username}\n";
        print "${prefix}   📧 Email: " . ($user->{email} || 'не указан') . "\n";
        print "${prefix}   🆔 ID: " . ($user->{id} || 'неизвестно') . "\n";
        print "${prefix}   📅 Создан: " . ($user->{created_at} || 'неизвестно') . "\n";
        print "${prefix}   🟢 Статус: " . ($user->{status} || 'неизвестно') . "\n";
        
        if ($user->{last_seen}) {
            print "${prefix}   👁️  Последний вход: $user->{last_seen}\n";
        }
    }
}

sub test_session_security {
    my ($user_session, $username) = @_;
    
    print "   🔒 Тест безопасности сессии для $username:\n";
    
    # Проверяем что статус авторизации корректен
    my $auth_check = api_request('GET', '/api/auth/check', undef, $user_session);
    
    if ($auth_check && $auth_check->{success}) {
        print "      ✅ Сессия активна: $auth_check->{user}->{username}\n";
        
        # Проверяем доступ к защищенным ресурсам
        my $protected_resources = [
            '/api/conversations',
            '/api/notes',
            '/api/users/search?q=test'
        ];
        
        foreach my $resource (@$protected_resources) {
            my $access_test = api_request('GET', $resource, undef, $user_session);
            if ($access_test && !$access_test->{error}) {
                print "      ✅ Доступ к $resource\n";
            } else {
                print "      ❌ Нет доступа к $resource\n";
            }
        }
        
        return $auth_check->{user};
    } else {
        print "      ❌ Сессия не активна\n";
        return undef;
    }
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

# === РЕГИСТРАЦИЯ НОВЫХ ПОЛЬЗОВАТЕЛЕЙ ===

print "📝 РЕГИСТРАЦИЯ НОВЫХ ПОЛЬЗОВАТЕЛЕЙ:\n";

my $test_users = generate_test_users();
my @registered_users;

foreach my $user_data (@$test_users) {
    print "   👤 Регистрация пользователя '$user_data->{username}':\n";
    
    my $register_data = "username=$user_data->{username}&" .
                       "email=$user_data->{email}&" .
                       "password=$user_data->{password}&" .
                       "confirm_password=$user_data->{password}";
    
    my $register_result = api_request('POST', '/register', $register_data);
    
    if ($register_result && ($register_result->{success} || $register_result->{redirect})) {
        print "      ✅ Пользователь зарегистрирован\n";
        
        if ($register_result->{redirect}) {
            print "      🔄 Перенаправление: $register_result->{redirect}\n";
        }
        
        push @registered_users, $user_data;
    } else {
        print "      ❌ Ошибка регистрации\n";
        
        if ($register_result->{content} && $register_result->{content} =~ /существует/i) {
            print "      💡 Пользователь уже существует\n";
            push @registered_users, $user_data; # Добавляем для дальнейших тестов
        }
    }
    print "\n";
}

# === АВТОРИЗАЦИЯ ПОЛЬЗОВАТЕЛЕЙ ===

print "🔐 АВТОРИЗАЦИЯ ПОЛЬЗОВАТЕЛЕЙ:\n";

my @user_sessions;

foreach my $user_data (@registered_users) {
    print "   🔑 Вход пользователя '$user_data->{username}':\n";
    
    # Создаем отдельную сессию для каждого пользователя
    my $user_session = create_user_session();
    
    my $login_data = "username=$user_data->{username}&password=$user_data->{password}";
    my $login_result = api_request('POST', '/login', $login_data, $user_session);
    
    if ($login_result && ($login_result->{success} || $login_result->{redirect})) {
        print "      ✅ Авторизация успешна\n";
        
        # Тестируем сессию
        my $user_info = test_session_security($user_session, $user_data->{username});
        
        if ($user_info) {
            push @user_sessions, {
                session => $user_session,
                user_data => $user_data,
                user_info => $user_info
            };
        }
    } else {
        print "      ❌ Ошибка авторизации\n";
        
        if ($login_result->{details}) {
            print "      📋 Детали: " . ($login_result->{details}->{message} || 'неизвестно') . "\n";
        }
    }
    print "\n";
}

# === УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ ===

print "👥 УПРАВЛЕНИЕ ПОЛЬЗОВАТЕЛЯМИ:\n";

if (@user_sessions) {
    my $admin_session = $user_sessions[0]->{session}; # Используем первую сессию как админскую
    
    # Получение списка всех пользователей
    print "   📋 Получение списка пользователей:\n";
    
    my $users_list = api_request('GET', '/api/users/search?q=', undef, $admin_session);
    if ($users_list && ref($users_list) eq 'ARRAY') {
        print "      ✅ Найдено пользователей: " . scalar(@$users_list) . "\n\n";
        
        foreach my $user (@$users_list) {
            print_user_info($user, "      ");
            print "\n";
        }
    } else {
        print "      ⚠️  Список пользователей недоступен или пуст\n\n";
    }
    
    # Поиск конкретных пользователей
    print "   🔍 Поиск пользователей:\n";
    
    my @search_terms = ('admin', 'test', 'user');
    foreach my $term (@search_terms) {
        print "      🔎 Поиск '$term':\n";
        
        my $search_result = api_request('GET', "/api/users/search?q=$term", undef, $admin_session);
        if ($search_result && ref($search_result) eq 'ARRAY') {
            print "         📊 Найдено: " . scalar(@$search_result) . " пользователей\n";
            
            foreach my $user (@$search_result) {
                print "         👤 $user->{username} ($user->{email})\n";
            }
        } else {
            print "         📭 Пользователи не найдены\n";
        }
        print "\n";
    }
}

# === ТЕСТИРОВАНИЕ БЕЗОПАСНОСТИ ===

print "🛡️  ТЕСТИРОВАНИЕ БЕЗОПАСНОСТИ:\n";

# Тест множественных сессий
print "   🔐 Тест множественных одновременных сессий:\n";
if (@user_sessions >= 2) {
    foreach my $session_data (@user_sessions) {
        my $username = $session_data->{user_data}->{username};
        my $auth_check = api_request('GET', '/api/auth/check', undef, $session_data->{session});
        
        if ($auth_check && $auth_check->{success}) {
            print "      ✅ Сессия $username активна\n";
        } else {
            print "      ❌ Сессия $username неактивна\n";
        }
    }
} else {
    print "      ⚠️  Недостаточно сессий для тестирования\n";
}

# Тест неправильных учетных данных
print "\n   🚫 Тест неправильных учетных данных:\n";
my $invalid_attempts = [
    { username => 'nonexistent_user', password => 'any_password' },
    { username => 'admin', password => 'wrong_password' },
    { username => '', password => '' }
];

foreach my $invalid (@$invalid_attempts) {
    print "      🔑 Попытка входа: '$invalid->{username}' / '[скрыт]'\n";
    
    my $temp_session = create_user_session();
    my $invalid_data = "username=$invalid->{username}&password=$invalid->{password}";
    my $invalid_result = api_request('POST', '/login', $invalid_data, $temp_session);
    
    if ($invalid_result && $invalid_result->{error}) {
        print "         ✅ Корректно отклонен\n";
    } elsif ($invalid_result && $invalid_result->{success}) {
        print "         ❌ ПРОБЛЕМА БЕЗОПАСНОСТИ: вход разрешен!\n";
    } else {
        print "         ✅ Вход отклонен\n";
    }
}

# Тест доступа без авторизации
print "\n   🔒 Тест доступа к защищенным ресурсам без авторизации:\n";
my $unauthorized_session = create_user_session();
my $protected_endpoints = [
    '/api/conversations',
    '/api/notes',
    '/api/messages'
];

foreach my $endpoint (@$protected_endpoints) {
    my $unauthorized_access = api_request('GET', $endpoint, undef, $unauthorized_session);
    
    if ($unauthorized_access && $unauthorized_access->{error}) {
        print "      ✅ $endpoint: доступ заблокирован\n";
    } else {
        print "      ⚠️  $endpoint: возможно доступен без авторизации\n";
    }
}

print "\n";

# === ВЫХОД ИЗ СИСТЕМЫ ===

print "🚪 ВЫХОД ИЗ СИСТЕМЫ:\n";

if (@user_sessions) {
    # Тестируем выход для одного пользователя
    my $session_to_logout = $user_sessions[0];
    my $username = $session_to_logout->{user_data}->{username};
    
    print "   👋 Выход пользователя '$username':\n";
    
    my $logout_result = api_request('POST', '/api/auth/logout', {}, $session_to_logout->{session});
    
    if ($logout_result && ($logout_result->{success} || $logout_result->{redirect})) {
        print "      ✅ Выход выполнен успешно\n";
        
        # Проверяем что сессия действительно завершена
        print "   🔍 Проверка завершения сессии:\n";
        my $post_logout_check = api_request('GET', '/api/auth/check', undef, $session_to_logout->{session});
        
        if ($post_logout_check && !$post_logout_check->{success}) {
            print "      ✅ Сессия корректно завершена\n";
        } else {
            print "      ⚠️  Сессия может быть все еще активна\n";
        }
        
        # Проверяем доступ к защищенным ресурсам после выхода
        print "   🔒 Проверка блокировки ресурсов после выхода:\n";
        my $post_logout_access = api_request('GET', '/api/conversations', undef, $session_to_logout->{session});
        
        if ($post_logout_access && $post_logout_access->{error}) {
            print "      ✅ Доступ к защищенным ресурсам заблокирован\n";
        } else {
            print "      ⚠️  Доступ к защищенным ресурсам может быть открыт\n";
        }
    } else {
        print "      ❌ Ошибка выхода из системы\n";
    }
}

print "\n";

# === СТАТИСТИКА ПОЛЬЗОВАТЕЛЕЙ ===

print "📊 СТАТИСТИКА ПОЛЬЗОВАТЕЛЕЙ:\n";

if (@user_sessions) {
    my $stats_session = $user_sessions[-1]->{session}; # Используем последнюю активную сессию
    
    my $all_users = api_request('GET', '/api/users/search?q=', undef, $stats_session);
    if ($all_users && ref($all_users) eq 'ARRAY') {
        my %status_count;
        my %domain_count;
        my $total_users = scalar(@$all_users);
        
        foreach my $user (@$all_users) {
            # Статистика по статусам
            my $status = $user->{status} || 'unknown';
            $status_count{$status}++;
            
            # Статистика по доменам email
            if ($user->{email} && $user->{email} =~ /\@(.+)$/) {
                my $domain = $1;
                $domain_count{$domain}++;
            }
        }
        
        print "   📈 Общая статистика:\n";
        print "      👥 Всего пользователей: $total_users\n";
        print "      ➕ Зарегистрировано в сессии: " . scalar(@registered_users) . "\n";
        print "      🔐 Активных сессий: " . scalar(@user_sessions) . "\n";
        
        print "\n   🟢 Статистика по статусам:\n";
        foreach my $status (sort keys %status_count) {
            print "      $status: $status_count{$status} пользователей\n";
        }
        
        if (%domain_count) {
            print "\n   📧 Статистика по доменам email:\n";
            foreach my $domain (sort { $domain_count{$b} <=> $domain_count{$a} } keys %domain_count) {
                print "      \@$domain: $domain_count{$domain} пользователей\n";
            }
        }
    }
}

# === ОЧИСТКА ТЕСТОВЫХ ДАННЫХ ===

print "\n🧹 ОЧИСТКА ТЕСТОВЫХ ДАННЫХ:\n";
print "   ⚠️  Примечание: Удаление пользователей через API может быть не реализовано\n";

foreach my $user_data (@registered_users) {
    print "   🗑️  Попытка удаления пользователя '$user_data->{username}':\n";
    
    # Пробуем разные методы удаления
    my @delete_attempts = (
        { method => 'DELETE', endpoint => "/api/users/$user_data->{username}" },
        { method => 'POST', endpoint => '/api/users/delete', data => { username => $user_data->{username} } }
    );
    
    my $deleted = 0;
    foreach my $attempt (@delete_attempts) {
        my $delete_result = api_request($attempt->{method}, $attempt->{endpoint}, $attempt->{data});
        
        if ($delete_result && $delete_result->{success}) {
            print "      ✅ Пользователь удален\n";
            $deleted = 1;
            last;
        }
    }
    
    if (!$deleted) {
        print "      💡 API удаления пользователей не реализован\n";
        print "      🛠️  Ручное удаление из БД: DELETE FROM users WHERE username='$user_data->{username}'\n";
    }
}

print "\n📊 ИТОГОВЫЙ ОТЧЕТ:\n";
print "=" x 40 . "\n";

print "🎯 Выполненные операции:\n";
print "   ✅ Регистрация пользователей: " . scalar(@registered_users) . "\n";
print "   ✅ Авторизация пользователей: " . scalar(@user_sessions) . "\n";
print "   ✅ Тестирование безопасности сессий\n";
print "   ✅ Проверка доступа к защищенным ресурсам\n";
print "   ✅ Тестирование выхода из системы\n";

print "\n💡 РЕКОМЕНДАЦИИ ДЛЯ РАЗРАБОТКИ:\n";
print "   🔐 Добавьте хеширование паролей (bcrypt/scrypt)\n";
print "   🕐 Реализуйте истечение сессий\n";
print "   🚫 Добавьте защиту от брутфорса (rate limiting)\n";
print "   🔒 Используйте HTTPS в production\n";
print "   🍪 Настройте Secure и HttpOnly cookies\n";
print "   👥 Добавьте роли и права пользователей\n";
print "   📊 Реализуйте логирование действий пользователей\n";
print "   🔄 Добавьте двухфакторную аутентификацию\n";
print "   🗑️  Реализуйте API удаления пользователей\n";

print "\n🎉 ДЕМОНСТРАЦИЯ АВТОРИЗАЦИИ И УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ ЗАВЕРШЕНА!\n";

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите пример
    perl examples/auth_users.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request
    HTTP::Cookies
    JSON
    Time::HiRes
    POSIX

=head1 AUTHOR

MegaChat API Examples

=cut
