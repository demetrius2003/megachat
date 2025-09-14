#!/usr/bin/env perl
use strict;
use warnings;
use utf8;

=head1 NAME

01_check_components.pl - Проверка установленных Perl компонентов

=head1 DESCRIPTION

Этот скрипт проверяет наличие всех необходимых Perl модулей 
для корректной работы MegaChat приложения.

=cut

print "🔍 ПРОВЕРКА УСТАНОВЛЕННЫХ PERL КОМПОНЕНТОВ\n";
print "=" x 50 . "\n\n";

my @required_modules = (
    'Mojolicious',
    'Mojolicious::Lite', 
    'DBI',
    'DBD::SQLite',
    'JSON',
    'Digest::MD5',
    'Time::Piece',
    'Encode',
    'File::Spec',
    'File::Path',
    'Cwd'
);

my @optional_modules = (
    'Data::Dumper',
    'Test::More',
    'IO::Socket::SSL',
    'Mojo::JSON'
);

my $all_required_ok = 1;
my $perl_version_ok = 1;

# Проверка версии Perl
print "📋 ПРОВЕРКА ВЕРСИИ PERL:\n";
my $perl_version = $^V;
print "   Текущая версия: $perl_version\n";

if ($] < 5.020) {
    print "   ❌ ОШИБКА: Требуется Perl 5.20 или выше!\n";
    $perl_version_ok = 0;
} else {
    print "   ✅ Версия Perl подходит\n";
}
print "\n";

# Проверка обязательных модулей
print "📦 ПРОВЕРКА ОБЯЗАТЕЛЬНЫХ МОДУЛЕЙ:\n";
foreach my $module (@required_modules) {
    print "   $module: ";
    
    eval "require $module";
    if ($@) {
        print "❌ НЕ УСТАНОВЛЕН\n";
        print "      Установка: cpan $module\n";
        $all_required_ok = 0;
    } else {
        # Попытка получить версию
        my $version = '';
        eval {
            no strict 'refs';
            $version = ${"${module}::VERSION"} || 'неизвестно';
        };
        print "✅ установлен (версия: $version)\n";
    }
}
print "\n";

# Проверка дополнительных модулей
print "📦 ПРОВЕРКА ДОПОЛНИТЕЛЬНЫХ МОДУЛЕЙ:\n";
foreach my $module (@optional_modules) {
    print "   $module: ";
    
    eval "require $module";
    if ($@) {
        print "⚠️  не установлен (рекомендуется)\n";
    } else {
        my $version = '';
        eval {
            no strict 'refs';
            $version = ${"${module}::VERSION"} || 'неизвестно';
        };
        print "✅ установлен (версия: $version)\n";
    }
}
print "\n";

# Проверка системных возможностей
print "🔧 ПРОВЕРКА СИСТЕМНЫХ ВОЗМОЖНОСТЕЙ:\n";

# Проверка поддержки UTF-8
eval {
    use utf8;
    my $test = "тест";
    print "   UTF-8 поддержка: ✅ работает\n";
};
if ($@) {
    print "   UTF-8 поддержка: ❌ проблемы\n";
}

# Проверка создания файлов
eval {
    my $test_file = 'test_write_permission.tmp';
    open my $fh, '>', $test_file or die $!;
    print $fh "test";
    close $fh;
    unlink $test_file;
    print "   Права записи: ✅ есть\n";
};
if ($@) {
    print "   Права записи: ❌ нет ($@)\n";
}

# Проверка сетевых портов
print "   Проверка порта 3000: ";
eval {
    require IO::Socket::INET;
    my $socket = IO::Socket::INET->new(
        LocalAddr => '127.0.0.1',
        LocalPort => 3000,
        Proto     => 'tcp',
        Listen    => 1,
        Reuse     => 1
    );
    if ($socket) {
        print "✅ доступен\n";
        close($socket);
    } else {
        print "❌ занят или недоступен\n";
    }
};
if ($@) {
    print "❌ ошибка проверки ($@)\n";
}

print "\n";

# Итоговый результат
print "📊 ИТОГОВЫЙ РЕЗУЛЬТАТ:\n";
print "=" x 30 . "\n";

if ($perl_version_ok && $all_required_ok) {
    print "🎉 ВСЕ КОМПОНЕНТЫ ГОТОВЫ!\n";
    print "   Можно запускать MegaChat приложение.\n\n";
    
    print "💡 Команды для запуска:\n";
    print "   cd megachat\n";
    print "   perl megachat.pl\n";
    exit 0;
} else {
    print "❌ ОБНАРУЖЕНЫ ПРОБЛЕМЫ!\n\n";
    
    if (!$perl_version_ok) {
        print "🔄 Обновите Perl до версии 5.20+\n";
    }
    
    if (!$all_required_ok) {
        print "📦 Установите недостающие модули:\n";
        print "   cpan Mojolicious DBI DBD::SQLite\n";
    }
    
    print "\n❗ Исправьте проблемы и запустите тест снова.\n";
    exit 1;
}

__END__

=head1 USAGE

    perl tests/01_check_components.pl

=head1 AUTHOR

MegaChat Project

=cut
