#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use DBI;
use File::Spec;

=head1 NAME

02_check_database.pl - Проверка готовности и структуры базы данных

=head1 DESCRIPTION

Проверяет наличие, структуру и целостность SQLite базы данных MegaChat.
Создает тестовые данные если необходимо.

=cut

print "🗄️  ПРОВЕРКА БАЗЫ ДАННЫХ MEGACHAT\n";
print "=" x 50 . "\n\n";

# Путь к базе данных
my $db_path = File::Spec->catfile('megachat.db');
my $db_exists = -f $db_path;

print "📋 ИНФОРМАЦИЯ О БАЗЕ ДАННЫХ:\n";
print "   Путь: $db_path\n";
print "   Существует: " . ($db_exists ? "✅ да" : "❌ нет") . "\n";

if ($db_exists) {
    my $size = -s $db_path;
    print "   Размер: $size байт\n";
}
print "\n";

# Попытка подключения
print "🔌 ПРОВЕРКА ПОДКЛЮЧЕНИЯ:\n";
my $dbh;
eval {
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_path", "", "", {
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        sqlite_unicode => 1
    });
    print "   ✅ Подключение успешно\n";
};
if ($@) {
    print "   ❌ Ошибка подключения: $@\n";
    exit 1;
}

# Проверка структуры таблиц
print "\n📊 ПРОВЕРКА СТРУКТУРЫ ТАБЛИЦ:\n";

my @expected_tables = ('users', 'conversations', 'conversation_participants', 'messages', 'notes');
my %table_status;

# Получение списка существующих таблиц
my $tables_sth = $dbh->prepare("SELECT name FROM sqlite_master WHERE type='table'");
$tables_sth->execute();
my @existing_tables;
while (my ($table) = $tables_sth->fetchrow_array()) {
    push @existing_tables, $table;
}

foreach my $table (@expected_tables) {
    if (grep { $_ eq $table } @existing_tables) {
        print "   $table: ✅ существует\n";
        $table_status{$table} = 1;
        
        # Проверка количества записей
        my $count_sth = $dbh->prepare("SELECT COUNT(*) FROM $table");
        $count_sth->execute();
        my ($count) = $count_sth->fetchrow_array();
        print "      Записей: $count\n";
        
    } else {
        print "   $table: ❌ отсутствует\n";
        $table_status{$table} = 0;
    }
}

# Проверка структуры каждой таблицы
print "\n🔍 ДЕТАЛЬНАЯ ПРОВЕРКА СТРУКТУРЫ:\n";

# Проверка таблицы users
if ($table_status{users}) {
    print "   users:\n";
    my $pragma = $dbh->selectall_arrayref("PRAGMA table_info(users)");
    my @expected_cols = qw(id username email password_hash created_at status last_seen);
    my @actual_cols = map { $_->[1] } @$pragma;
    
    foreach my $col (@expected_cols) {
        if (grep { $_ eq $col } @actual_cols) {
            print "      ✅ $col\n";
        } else {
            print "      ❌ $col (отсутствует)\n";
        }
    }
}

# Проверка таблицы conversations
if ($table_status{conversations}) {
    print "   conversations:\n";
    my $pragma = $dbh->selectall_arrayref("PRAGMA table_info(conversations)");
    my @expected_cols = qw(id name description created_by created_at);
    my @actual_cols = map { $_->[1] } @$pragma;
    
    foreach my $col (@expected_cols) {
        if (grep { $_ eq $col } @actual_cols) {
            print "      ✅ $col\n";
        } else {
            print "      ❌ $col (отсутствует)\n";
        }
    }
}

# Проверка таблицы messages
if ($table_status{messages}) {
    print "   messages:\n";
    my $pragma = $dbh->selectall_arrayref("PRAGMA table_info(messages)");
    my @expected_cols = qw(id conversation_id sender_id content message_type file_path created_at);
    my @actual_cols = map { $_->[1] } @$pragma;
    
    foreach my $col (@expected_cols) {
        if (grep { $_ eq $col } @actual_cols) {
            print "      ✅ $col\n";
        } else {
            print "      ❌ $col (отсутствует)\n";
        }
    }
}

# Проверка целостности данных
print "\n🔗 ПРОВЕРКА ЦЕЛОСТНОСТИ ДАННЫХ:\n";

# Проверка foreign key constraints
eval {
    # Проверяем что все conversation_participants ссылаются на существующие users и conversations
    my $check1 = $dbh->selectrow_array("
        SELECT COUNT(*) FROM conversation_participants cp 
        LEFT JOIN users u ON cp.user_id = u.id 
        WHERE u.id IS NULL
    ");
    
    if ($check1 > 0) {
        print "   ❌ Найдены участники чатов без соответствующих пользователей: $check1\n";
    } else {
        print "   ✅ Все участники чатов корректно связаны с пользователями\n";
    }
    
    my $check2 = $dbh->selectrow_array("
        SELECT COUNT(*) FROM messages m 
        LEFT JOIN conversations c ON m.conversation_id = c.id 
        WHERE c.id IS NULL
    ");
    
    if ($check2 > 0) {
        print "   ❌ Найдены сообщения без соответствующих чатов: $check2\n";
    } else {
        print "   ✅ Все сообщения корректно связаны с чатами\n";
    }
};

# Проверка индексов
print "\n📇 ПРОВЕРКА ИНДЕКСОВ:\n";
my $indexes = $dbh->selectall_arrayref("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'");
if (@$indexes) {
    foreach my $index (@$indexes) {
        print "   ✅ $index->[0] на таблице $index->[1]\n";
    }
} else {
    print "   ⚠️  Пользовательские индексы не найдены\n";
}

# Тестирование производительности
print "\n⚡ ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ:\n";
my $start_time = time();

# Тест вставки
eval {
    $dbh->begin_work();
    my $test_sth = $dbh->prepare("INSERT INTO users (username, email, password_hash, created_at, status) VALUES (?, ?, ?, ?, ?)");
    for my $i (1..100) {
        $test_sth->execute("test_user_$i", "test$i\@example.com", "test_hash", time(), "offline");
    }
    $dbh->rollback(); # Откатываем тестовые данные
    
    my $insert_time = time() - $start_time;
    print "   ✅ Вставка 100 записей: ${insert_time}с\n";
};
if ($@) {
    print "   ❌ Ошибка теста вставки: $@\n";
}

# Тест выборки
$start_time = time();
eval {
    my $select_sth = $dbh->prepare("SELECT * FROM users LIMIT 100");
    $select_sth->execute();
    my $results = $select_sth->fetchall_arrayref();
    
    my $select_time = time() - $start_time;
    print "   ✅ Выборка записей: ${select_time}с\n";
};
if ($@) {
    print "   ❌ Ошибка теста выборки: $@\n";
}

# Создание тестовых данных если их нет
print "\n🧪 СОЗДАНИЕ ТЕСТОВЫХ ДАННЫХ:\n";

# Проверяем количество пользователей
my ($user_count) = $dbh->selectrow_array("SELECT COUNT(*) FROM users");
if ($user_count < 3) {
    print "   📝 Создаем тестовых пользователей...\n";
    
    my $users = [
        ['admin', 'admin@megachat.local', 'admin_hash', 'online'],
        ['user1', 'user1@megachat.local', 'user1_hash', 'offline'], 
        ['user2', 'user2@megachat.local', 'user2_hash', 'offline']
    ];
    
    my $user_sth = $dbh->prepare("INSERT OR IGNORE INTO users (username, email, password_hash, created_at, status) VALUES (?, ?, ?, ?, ?)");
    foreach my $user (@$users) {
        $user_sth->execute($user->[0], $user->[1], $user->[2], time(), $user->[3]);
        print "      ✅ Пользователь: $user->[0]\n";
    }
} else {
    print "   ℹ️  Тестовые пользователи уже существуют ($user_count)\n";
}

$dbh->disconnect();

print "\n📊 ИТОГОВЫЙ РЕЗУЛЬТАТ:\n";
print "=" x 30 . "\n";

my $all_tables_ok = 1;
foreach my $table (@expected_tables) {
    if (!$table_status{$table}) {
        $all_tables_ok = 0;
        last;
    }
}

if ($all_tables_ok) {
    print "🎉 БАЗА ДАННЫХ ГОТОВА К РАБОТЕ!\n";
    print "   Все таблицы созданы и доступны.\n";
    print "   Тестовые данные загружены.\n\n";
    
    print "💡 Для очистки тестовых данных:\n";
    print "   DELETE FROM users WHERE username LIKE 'test_user_%';\n";
    exit 0;
} else {
    print "❌ ПРОБЛЕМЫ С БАЗОЙ ДАННЫХ!\n";
    print "   Запустите основное приложение для создания таблиц.\n";
    print "   perl megachat.pl\n";
    exit 1;
}

__END__

=head1 USAGE

    cd megachat
    perl tests/02_check_database.pl

=head1 AUTHOR

MegaChat Project

=cut
