#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use File::Spec;
use File::Basename;
use Cwd;
use POSIX qw(strftime);

=head1 NAME

run_all_tests.pl - Главный тест-раннер для MegaChat

=head1 DESCRIPTION

Запускает все тесты проекта MegaChat в правильном порядке,
собирает статистику, генерирует отчеты и предоставляет
удобный интерфейс для управления тестированием.

=cut

# Включаем UTF-8 для корректного отображения русского текста
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "🧪 MEGACHAT - КОМПЛЕКСНОЕ ТЕСТИРОВАНИЕ\n";
print "=" x 60 . "\n\n";

# Получаем путь к директории с тестами
my $script_dir = dirname(File::Spec->rel2abs($0));
my $project_root = dirname($script_dir);

print "📁 ИНФОРМАЦИЯ О ПРОЕКТЕ:\n";
print "   Корневая директория: $project_root\n";
print "   Директория тестов: $script_dir\n";
print "   Время запуска: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n\n";

# Проверяем что мы в правильной директории
chdir($project_root) or die "Не удалось перейти в директорию проекта: $!";
print "   ✅ Рабочая директория установлена: " . getcwd() . "\n\n";

# Определение тестов в порядке выполнения
my @tests = (
    {
        name => 'Проверка компонентов',
        file => '01_check_components.pl',
        description => 'Проверка установленных Perl модулей и зависимостей',
        critical => 1
    },
    {
        name => 'Проверка базы данных',
        file => '02_check_database.pl', 
        description => 'Проверка структуры и целостности SQLite БД',
        critical => 1
    },
    {
        name => 'Проверка API',
        file => '03_check_api.pl',
        description => 'Тестирование REST API эндпоинтов',
        critical => 0,
        requires_server => 1
    },
    {
        name => 'Проверка WebSocket',
        file => '04_check_websocket.pl',
        description => 'Тестирование WebSocket функциональности',
        critical => 0,
        requires_server => 1
    },
    {
        name => 'Проверка авторизации',
        file => '05_check_auth.pl',
        description => 'Тестирование системы аутентификации',
        critical => 0,
        requires_server => 1
    }
);

# Обработка аргументов командной строки
my %options = (
    verbose => 0,
    skip_server_tests => 0,
    quick => 0,
    help => 0
);

foreach my $arg (@ARGV) {
    if ($arg eq '--verbose' || $arg eq '-v') {
        $options{verbose} = 1;
    } elsif ($arg eq '--skip-server' || $arg eq '-s') {
        $options{skip_server_tests} = 1;
    } elsif ($arg eq '--quick' || $arg eq '-q') {
        $options{quick} = 1;
    } elsif ($arg eq '--help' || $arg eq '-h') {
        $options{help} = 1;
    }
}

if ($options{help}) {
    print_help();
    exit 0;
}

# Проверка доступности тестовых файлов
print "🔍 ПРОВЕРКА ДОСТУПНОСТИ ТЕСТОВ:\n";
my @available_tests;

foreach my $test (@tests) {
    my $test_path = File::Spec->catfile($script_dir, $test->{file});
    if (-f $test_path && -r $test_path) {
        push @available_tests, $test;
        print "   ✅ $test->{name}\n";
    } else {
        print "   ❌ $test->{name} - файл не найден: $test_path\n";
    }
}

print "\n   📊 Доступно тестов: " . scalar(@available_tests) . "/" . scalar(@tests) . "\n\n";

if (!@available_tests) {
    print "❌ Тестовые файлы не найдены!\n";
    exit 1;
}

# Проверка запущен ли сервер (для тестов требующих сервер)
my $server_running = 0;
if (!$options{skip_server_tests}) {
    print "🌐 ПРОВЕРКА СТАТУСА СЕРВЕРА:\n";
    
    eval {
        require IO::Socket::INET;
        my $socket = IO::Socket::INET->new(
            PeerHost => 'localhost',
            PeerPort => 3000,
            Proto    => 'tcp',
            Timeout  => 3
        );
        if ($socket) {
            $server_running = 1;
            close($socket);
        }
    };
    
    if ($server_running) {
        print "   ✅ Сервер запущен на localhost:3000\n";
    } else {
        print "   ⚠️  Сервер не запущен\n";
        print "   💡 Тесты требующие сервер будут пропущены\n";
        print "   💡 Для запуска сервера: perl megachat.pl\n";
    }
    print "\n";
}

# Запуск тестов
print "🚀 ЗАПУСК ТЕСТОВ:\n";
print "=" x 40 . "\n\n";

my $start_time = time();
my @results;

foreach my $test (@available_tests) {
    # Пропускаем тесты требующие сервер, если он не запущен
    if ($test->{requires_server} && !$server_running) {
        print "⏭️  ПРОПУСК: $test->{name} (сервер не запущен)\n\n";
        push @results, {
            test => $test,
            status => 'skipped',
            reason => 'server not running'
        };
        next;
    }
    
    print "🔬 ЗАПУСК: $test->{name}\n";
    print "   Описание: $test->{description}\n";
    
    my $test_path = File::Spec->catfile($script_dir, $test->{file});
    my $test_start = time();
    
    # Запуск теста
    my $output = '';
    my $exit_code;
    
    if ($options{verbose}) {
        print "   Команда: perl $test_path\n";
        $exit_code = system("perl", $test_path);
    } else {
        # Захватываем вывод
        $output = `perl "$test_path" 2>&1`;
        $exit_code = $?;
    }
    
    my $test_time = sprintf("%.2f", time() - $test_start);
    
    # Анализ результата
    my $success = ($exit_code == 0);
    my $status = $success ? 'passed' : 'failed';
    
    if ($success) {
        print "   ✅ ПРОЙДЕН за ${test_time}с\n";
    } else {
        print "   ❌ ПРОВАЛЕН за ${test_time}с (код: $exit_code)\n";
        
        if (!$options{verbose} && $output) {
            # Показываем последние строки вывода при ошибке
            my @lines = split(/\n/, $output);
            my $show_lines = 5;
            if (@lines > $show_lines) {
                print "   📋 Последние строки вывода:\n";
                foreach my $line (@lines[-$show_lines..-1]) {
                    print "      $line\n";
                }
            } else {
                print "   📋 Вывод теста:\n";
                foreach my $line (@lines) {
                    print "      $line\n";
                }
            }
        }
    }
    
    push @results, {
        test => $test,
        status => $status,
        time => $test_time,
        exit_code => $exit_code,
        output => $output
    };
    
    print "\n";
    
    # Останавливаемся на критических ошибках (если не quick режим)
    if (!$success && $test->{critical} && !$options{quick}) {
        print "💥 КРИТИЧЕСКАЯ ОШИБКА!\n";
        print "   Тест '$test->{name}' является критическим и провален.\n";
        print "   Дальнейшее тестирование остановлено.\n\n";
        last;
    }
}

my $total_time = sprintf("%.2f", time() - $start_time);

# Генерация отчета
print "📊 ИТОГОВЫЙ ОТЧЕТ\n";
print "=" x 50 . "\n\n";

my $total_tests = scalar(@results);
my $passed = grep { $_->{status} eq 'passed' } @results;
my $failed = grep { $_->{status} eq 'failed' } @results;
my $skipped = grep { $_->{status} eq 'skipped' } @results;

print "📈 СТАТИСТИКА:\n";
print "   Всего тестов: $total_tests\n";
print "   Пройдено: $passed ✅\n";
print "   Провалено: $failed ❌\n";
print "   Пропущено: $skipped ⏭️\n";
print "   Время выполнения: ${total_time}с\n";
print "   Процент успеха: " . sprintf("%.1f", ($passed/($total_tests-$skipped))*100) . "%\n\n" if ($total_tests - $skipped) > 0;

# Детальные результаты
print "📋 ДЕТАЛЬНЫЕ РЕЗУЛЬТАТЫ:\n";
foreach my $result (@results) {
    my $icon = $result->{status} eq 'passed' ? '✅' : 
               $result->{status} eq 'failed' ? '❌' : '⏭️';
    
    printf "   %s %-30s %s", $icon, $result->{test}->{name}, 
           $result->{status} eq 'skipped' ? "($result->{reason})" : 
           $result->{time} ? "(${result->{time}}с)" : "";
    print "\n";
}

# Рекомендации
print "\n💡 РЕКОМЕНДАЦИИ:\n";

if ($failed > 0) {
    print "   🔧 Исправьте провалившиеся тесты перед продолжением\n";
    
    my @critical_failed = grep { $_->{status} eq 'failed' && $_->{test}->{critical} } @results;
    if (@critical_failed) {
        print "   ⚠️  Критические тесты провалены - приложение может не работать\n";
    }
}

if ($skipped > 0) {
    print "   🌐 Запустите сервер для полного тестирования: perl megachat.pl\n";
}

if ($passed == $total_tests) {
    print "   🎉 Все тесты пройдены! Приложение готово к использованию\n";
}

# Создание лог-файла
my $log_file = File::Spec->catfile($script_dir, 'test_results.log');
write_log_file($log_file, \@results, $total_time);
print "\n📝 Подробный лог сохранен: $log_file\n";

# Определение итогового статуса
my $exit_status = 0;
if ($failed > 0) {
    my @critical_failed = grep { $_->{status} eq 'failed' && $_->{test}->{critical} } @results;
    $exit_status = @critical_failed ? 2 : 1;
}

print "\n" . "=" x 60 . "\n";
if ($exit_status == 0) {
    print "🎊 ТЕСТИРОВАНИЕ ЗАВЕРШЕНО УСПЕШНО!\n";
} elsif ($exit_status == 1) {
    print "⚠️  ТЕСТИРОВАНИЕ ЗАВЕРШЕНО С ПРЕДУПРЕЖДЕНИЯМИ\n";
} else {
    print "💥 ТЕСТИРОВАНИЕ ЗАВЕРШЕНО С КРИТИЧЕСКИМИ ОШИБКАМИ!\n";
}

exit $exit_status;

# Вспомогательные функции

sub print_help {
    print <<'HELP';
🧪 MegaChat Test Runner - Справка

ИСПОЛЬЗОВАНИЕ:
    perl run_all_tests.pl [ОПЦИИ]

ОПЦИИ:
    -h, --help          Показать эту справку
    -v, --verbose       Подробный вывод всех тестов
    -s, --skip-server   Пропустить тесты требующие сервер
    -q, --quick         Быстрый режим (не останавливаться на критических ошибках)

ПРИМЕРЫ:
    perl run_all_tests.pl                    # Обычный запуск
    perl run_all_tests.pl --verbose          # С подробным выводом
    perl run_all_tests.pl --skip-server      # Без серверных тестов
    perl run_all_tests.pl -v -q              # Подробно и быстро

ОПИСАНИЕ ТЕСТОВ:
    01_check_components.pl    Проверка Perl модулей
    02_check_database.pl      Проверка базы данных  
    03_check_api.pl          Тестирование API
    04_check_websocket.pl    Тестирование WebSocket
    05_check_auth.pl         Тестирование авторизации

КОДЫ ВОЗВРАТА:
    0    Все тесты пройдены
    1    Некритические ошибки
    2    Критические ошибки

HELP
}

sub write_log_file {
    my ($log_file, $results, $total_time) = @_;
    
    open my $fh, '>:encoding(UTF-8)', $log_file or return;
    
    print $fh "MegaChat Test Results\n";
    print $fh "=====================\n";
    print $fh "Timestamp: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
    print $fh "Total Time: ${total_time}s\n\n";
    
    foreach my $result (@$results) {
        print $fh "Test: $result->{test}->{name}\n";
        print $fh "File: $result->{test}->{file}\n";
        print $fh "Status: $result->{status}\n";
        print $fh "Time: " . ($result->{time} || 'N/A') . "s\n";
        if ($result->{exit_code}) {
            print $fh "Exit Code: $result->{exit_code}\n";
        }
        if ($result->{output}) {
            print $fh "Output:\n$result->{output}\n";
        }
        print $fh "\n" . "-" x 50 . "\n\n";
    }
    
    close $fh;
}

__END__

=head1 USAGE

    cd megachat
    perl tests/run_all_tests.pl [options]

=head1 OPTIONS

    --verbose     Подробный вывод
    --skip-server Пропустить серверные тесты  
    --quick       Быстрый режим
    --help        Справка

=head1 AUTHOR

MegaChat Project

=cut
