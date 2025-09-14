#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use JSON;
use HTTP::Request;
use Time::HiRes qw(time);

=head1 NAME

03_check_api.pl - Проверка API эндпоинтов MegaChat

=head1 DESCRIPTION

Тестирует все REST API эндпоинты приложения MegaChat.
Проверяет доступность, корректность ответов и производительность.

=cut

print "🌐 ПРОВЕРКА API ЭНДПОИНТОВ MEGACHAT\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 10;

# Создание HTTP клиента
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-API-Tester/1.0'
);

my $json = JSON->new->utf8;

# Проверка доступности сервера
print "🔌 ПРОВЕРКА ДОСТУПНОСТИ СЕРВЕРА:\n";
print "   URL: $base_url\n";

my $start_time = time();
my $response = $ua->get($base_url);
my $response_time = sprintf("%.3f", time() - $start_time);

if ($response->is_success) {
    print "   ✅ Сервер доступен (время ответа: ${response_time}с)\n";
    print "   📄 Content-Type: " . ($response->header('Content-Type') || 'не указан') . "\n";
} else {
    print "   ❌ Сервер недоступен: " . $response->status_line . "\n";
    print "   💡 Убедитесь что приложение запущено: perl megachat.pl\n";
    exit 1;
}
print "\n";

# Определение тестов API
my @api_tests = (
    {
        name => 'Главная страница',
        method => 'GET',
        url => '/',
        expected_status => 200,
        content_check => sub { $_[0] =~ /MegaChat|html/i }
    },
    {
        name => 'Проверка авторизации (без логина)',
        method => 'GET', 
        url => '/api/auth/check',
        expected_status => 200,
        json_response => 1,
        content_check => sub { 
            my $data = eval { $json->decode($_[0]) };
            return $data && exists $data->{success};
        }
    },
    {
        name => 'Поиск пользователей',
        method => 'GET',
        url => '/api/users/search?q=admin',
        expected_status => 200,
        json_response => 1,
        content_check => sub {
            my $data = eval { $json->decode($_[0]) };
            return $data && ref($data) eq 'ARRAY';
        }
    },
    {
        name => 'Список чатов (без авторизации)',
        method => 'GET',
        url => '/api/conversations',
        expected_status => [200, 401], # Может быть и unauthorized
        json_response => 1
    },
    {
        name => 'Поиск сообщений',
        method => 'GET',
        url => '/api/messages/search?q=test&conversation_id=1',
        expected_status => [200, 404],
        json_response => 1
    },
    {
        name => 'Получение заметок',
        method => 'GET',
        url => '/api/notes',
        expected_status => [200, 401],
        json_response => 1
    },
    {
        name => 'Страница логина',
        method => 'GET',
        url => '/login',
        expected_status => 200,
        content_check => sub { $_[0] =~ /login|вход/i }
    },
    {
        name => 'Страница регистрации',
        method => 'GET',
        url => '/register', 
        expected_status => 200,
        content_check => sub { $_[0] =~ /register|регистрация/i }
    },
    {
        name => 'Несуществующая страница',
        method => 'GET',
        url => '/nonexistent-page',
        expected_status => 404
    }
);

# Выполнение тестов API
print "🧪 ВЫПОЛНЕНИЕ ТЕСТОВ API:\n";
my $total_tests = scalar @api_tests;
my $passed_tests = 0;
my $total_time = 0;

foreach my $test (@api_tests) {
    print "   $test->{name}: ";
    
    # Выполнение запроса
    my $start = time();
    my $req_response;
    
    if ($test->{method} eq 'GET') {
        $req_response = $ua->get($base_url . $test->{url});
    } elsif ($test->{method} eq 'POST') {
        my $req = HTTP::Request->new('POST', $base_url . $test->{url});
        $req->header('Content-Type' => 'application/json') if $test->{json_request};
        $req->content($test->{data} || '');
        $req_response = $ua->request($req);
    }
    
    my $test_time = sprintf("%.3f", time() - $start);
    $total_time += $test_time;
    
    # Проверка статуса
    my $status_ok = 0;
    if (ref($test->{expected_status}) eq 'ARRAY') {
        $status_ok = grep { $_ == $req_response->code } @{$test->{expected_status}};
    } else {
        $status_ok = $req_response->code == $test->{expected_status};
    }
    
    if (!$status_ok) {
        print "❌ FAIL (статус: " . $req_response->code . ", ожидался: " . 
              (ref($test->{expected_status}) ? join('/', @{$test->{expected_status}}) : $test->{expected_status}) . 
              ", время: ${test_time}с)\n";
        next;
    }
    
    # Проверка содержимого
    my $content_ok = 1;
    if ($test->{content_check}) {
        $content_ok = $test->{content_check}->($req_response->content);
    }
    
    # Проверка JSON формата
    if ($test->{json_response} && $req_response->is_success) {
        eval { $json->decode($req_response->content) };
        if ($@) {
            print "❌ FAIL (некорректный JSON, время: ${test_time}с)\n";
            next;
        }
    }
    
    if ($content_ok) {
        print "✅ PASS (время: ${test_time}с)\n";
        $passed_tests++;
    } else {
        print "❌ FAIL (некорректное содержимое, время: ${test_time}с)\n";
    }
}

print "\n";

# Тест производительности
print "⚡ ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ:\n";

my $perf_tests = [
    { url => '/api/auth/check', requests => 10 },
    { url => '/api/users/search?q=a', requests => 5 },
    { url => '/', requests => 3 }
];

foreach my $perf (@$perf_tests) {
    print "   $perf->{url} ($perf->{requests} запросов): ";
    
    my $perf_start = time();
    my $success_count = 0;
    
    for (1..$perf->{requests}) {
        my $resp = $ua->get($base_url . $perf->{url});
        $success_count++ if $resp->is_success;
    }
    
    my $perf_time = time() - $perf_start;
    my $avg_time = sprintf("%.3f", $perf_time / $perf->{requests});
    my $rps = sprintf("%.1f", $perf->{requests} / $perf_time);
    
    if ($success_count == $perf->{requests}) {
        print "✅ среднее: ${avg_time}с, RPS: $rps\n";
    } else {
        print "⚠️  успешно: $success_count/$perf->{requests}, среднее: ${avg_time}с\n";
    }
}

# Тест статических файлов
print "\n📁 ПРОВЕРКА СТАТИЧЕСКИХ ФАЙЛОВ:\n";

my @static_files = (
    '/static/css/main.css',
    '/static/js/main.js',
    '/static/js/chat.js',
    '/static/js/ui.js'
);

foreach my $file (@static_files) {
    print "   $file: ";
    my $resp = $ua->get($base_url . $file);
    
    if ($resp->is_success) {
        my $size = length($resp->content);
        print "✅ доступен (размер: $size байт)\n";
    } else {
        print "❌ недоступен (" . $resp->status_line . ")\n";
    }
}

# Тест заголовков безопасности
print "\n🔒 ПРОВЕРКА ЗАГОЛОВКОВ БЕЗОПАСНОСТИ:\n";

my $security_resp = $ua->get($base_url);
my $headers = $security_resp->headers;

my @security_headers = (
    'X-Frame-Options',
    'X-XSS-Protection', 
    'X-Content-Type-Options',
    'Strict-Transport-Security',
    'Content-Security-Policy'
);

foreach my $header (@security_headers) {
    my $value = $headers->header($header);
    if ($value) {
        print "   $header: ✅ установлен ($value)\n";
    } else {
        print "   $header: ⚠️  не установлен (рекомендуется)\n";
    }
}

print "\n📊 ИТОГОВЫЙ РЕЗУЛЬТАТ:\n";
print "=" x 30 . "\n";

my $avg_response_time = sprintf("%.3f", $total_time / $total_tests);

print "📈 Статистика:\n";
print "   Пройдено тестов: $passed_tests/$total_tests\n";
print "   Процент успеха: " . sprintf("%.1f", ($passed_tests/$total_tests)*100) . "%\n";
print "   Общее время: " . sprintf("%.3f", $total_time) . "с\n";
print "   Среднее время ответа: ${avg_response_time}с\n\n";

if ($passed_tests == $total_tests) {
    print "🎉 ВСЕ API ТЕСТЫ ПРОЙДЕНЫ!\n";
    print "   API готово к использованию.\n";
    exit 0;
} elsif ($passed_tests >= $total_tests * 0.8) {
    print "⚠️  БОЛЬШИНСТВО ТЕСТОВ ПРОЙДЕНО\n";
    print "   API функционирует с незначительными проблемами.\n";
    exit 0;
} else {
    print "❌ КРИТИЧЕСКИЕ ПРОБЛЕМЫ С API!\n";
    print "   Проверьте конфигурацию и доступность сервера.\n";
    exit 1;
}

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите тест
    perl tests/03_check_api.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    JSON  
    HTTP::Request
    Time::HiRes

=head1 AUTHOR

MegaChat Project

=cut
