#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Cookies;
use JSON;
use Data::Dumper;
use POSIX qw(strftime);

=head1 NAME

notes_crud.pl - CRUD операции с заметками через MegaChat API

=head1 DESCRIPTION

Демонстрирует полный набор операций Create, Read, Update, Delete
для работы с заметками через REST API MegaChat приложения.

=cut

# Включаем UTF-8 вывод
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "📝 MEGACHAT API - CRUD ОПЕРАЦИИ С ЗАМЕТКАМИ\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 30;

# HTTP клиент с поддержкой cookies
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-Notes-Example/1.0',
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

sub print_note_info {
    my ($note, $prefix) = @_;
    $prefix //= '';
    
    if (ref($note) eq 'HASH') {
        print "${prefix}📋 Заметка #$note->{id}: '$note->{title}'\n";
        print "${prefix}   Содержание: " . substr($note->{content} || '', 0, 100) . 
              (length($note->{content} || '') > 100 ? '...' : '') . "\n";
        print "${prefix}   Автор: " . ($note->{username} || $note->{user_id} || 'неизвестно') . "\n";
        print "${prefix}   Создана: " . ($note->{created_at} || 'неизвестно') . "\n";
        
        if ($note->{tags} && ref($note->{tags}) eq 'ARRAY') {
            print "${prefix}   Теги: " . join(', ', @{$note->{tags}}) . "\n";
        }
        
        if ($note->{is_favorite}) {
            print "${prefix}   ⭐ Избранная\n";
        }
    }
}

sub generate_sample_notes {
    return [
        {
            title => "API Демо заметка " . time(),
            content => "Это демонстрационная заметка созданная через API.\n\nСодержит:\n- Множественные строки\n- Список элементов\n- 📝 Эмодзи\n\nСоздана: " . strftime("%Y-%m-%d %H:%M:%S", localtime),
            tags => ['demo', 'api', 'test']
        },
        {
            title => "Техническая заметка",
            content => "# Технические детали\n\n## API Endpoints\n- GET /api/notes - получить заметки\n- POST /api/notes - создать заметку\n- PUT /api/notes/:id - обновить заметку\n- DELETE /api/notes/:id - удалить заметку\n\n## Формат данных\n```json\n{\n  \"title\": \"Заголовок\",\n  \"content\": \"Содержание\",\n  \"tags\": [\"тег1\", \"тег2\"]\n}\n```",
            tags => ['technical', 'documentation', 'api']
        },
        {
            title => "Список задач",
            content => "TODO список:\n\n☐ Реализовать поиск по заметкам\n☐ Добавить категории\n☐ Экспорт в различные форматы\n☑ CRUD операции через API\n☐ Синхронизация между устройствами\n☐ Markdown поддержка\n☐ Прикрепление файлов",
            tags => ['todo', 'tasks', 'planning']
        },
        {
            title => "Мысли и идеи",
            content => "Случайные мысли:\n\n💡 Идея: Добавить автоматическое сохранение заметок\n🎯 Цель: Улучшить UX интерфейса\n🚀 План: Постепенное развитие функциональности\n\n\"Хорошие заметки - основа продуктивности\" - Кто-то умный\n\nИнтересные факты:\n- Средняя заметка содержит 50-200 слов\n- 80% заметок читаются только один раз\n- Структурированные заметки эффективнее на 40%",
            tags => ['ideas', 'thoughts', 'productivity']
        }
    ];
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

# === CREATE - СОЗДАНИЕ ЗАМЕТОК ===

print "➕ CREATE - СОЗДАНИЕ НОВЫХ ЗАМЕТОК:\n";

my @new_notes;
my $sample_notes = generate_sample_notes();

foreach my $i (0..$#$sample_notes) {
    my $note_data = $sample_notes->[$i];
    
    print "   " . ($i + 1) . "️⃣ Создание заметки '$note_data->{title}':\n";
    
    my $result = api_request('POST', '/api/notes', $note_data);
    if ($result && $result->{success}) {
        push @new_notes, { %$result, %$note_data };
        print "      ✅ Создана заметка ID: $result->{id}\n";
    } else {
        print "      ❌ Ошибка создания заметки\n";
        if ($result && $result->{error}) {
            print "      📋 Детали: $result->{error}\n";
        }
    }
}

print "\n";

# === READ - ПОЛУЧЕНИЕ СПИСКА ЗАМЕТОК ===

print "📖 READ - ПОЛУЧЕНИЕ СПИСКА ЗАМЕТОК:\n";

my $all_notes = api_request('GET', '/api/notes');
if ($all_notes && ref($all_notes) eq 'ARRAY') {
    print "   📋 Всего заметок: " . scalar(@$all_notes) . "\n\n";
    
    # Сортируем по дате создания (новые сверху)
    my @sorted_notes = sort { ($b->{created_at} || 0) cmp ($a->{created_at} || 0) } @$all_notes;
    
    foreach my $note (@sorted_notes) {
        print_note_info($note, "   ");
        print "\n";
    }
} else {
    print "   ❌ Ошибка получения списка заметок\n\n";
}

# === READ - ДЕТАЛЬНОЕ ЧТЕНИЕ ЗАМЕТКИ ===

if (@new_notes) {
    print "🔍 READ - ПОЛУЧЕНИЕ ДЕТАЛЬНОЙ ИНФОРМАЦИИ О ЗАМЕТКЕ:\n";
    
    my $note_id = $new_notes[0]->{id};
    print "   Получаем полную информацию о заметке #$note_id:\n";
    
    my $note_details = api_request('GET', "/api/notes/$note_id");
    if ($note_details && !$note_details->{error}) {
        print "   ✅ Детальная информация получена:\n";
        print_note_info($note_details, "      ");
        
        print "\n      📝 Полное содержание:\n";
        my $content = $note_details->{content} || '';
        foreach my $line (split /\n/, $content) {
            print "         $line\n";
        }
    } else {
        print "   ❌ Ошибка получения детальной информации\n";
    }
    print "\n";
}

# === UPDATE - ОБНОВЛЕНИЕ ЗАМЕТОК ===

print "✏️  UPDATE - ОБНОВЛЕНИЕ ЗАМЕТОК:\n";

if (@new_notes) {
    my $note_to_update = $new_notes[0];
    my $note_id = $note_to_update->{id};
    
    print "   Обновление заметки #$note_id:\n";
    
    my $update_data = {
        title => $note_to_update->{title} . " (ОБНОВЛЕНО)",
        content => $note_to_update->{content} . "\n\n--- ОБНОВЛЕНИЕ ---\nДобавлена информация через API: " . strftime("%Y-%m-%d %H:%M:%S", localtime),
        tags => [@{$note_to_update->{tags} || []}, 'updated', 'modified']
    };
    
    my $update_result = api_request('PUT', "/api/notes/$note_id", $update_data);
    if ($update_result && $update_result->{success}) {
        print "      ✅ Заметка обновлена\n";
        
        # Проверяем обновление
        print "   Проверка обновления:\n";
        my $updated_note = api_request('GET', "/api/notes/$note_id");
        if ($updated_note && $updated_note->{title} =~ /ОБНОВЛЕНО/) {
            print "      ✅ Изменения применены корректно\n";
        }
    } else {
        print "      ❌ Ошибка обновления (код: " . ($update_result->{code} || 'unknown') . ")\n";
        if ($update_result->{code} && $update_result->{code} == 404) {
            print "      💡 UPDATE операция может быть не реализована\n";
        }
    }
} else {
    print "   ⚠️  Нет заметок для обновления\n";
}

print "\n";

# === DELETE - УДАЛЕНИЕ ЗАМЕТОК ===

print "🗑️  DELETE - УДАЛЕНИЕ ЗАМЕТОК:\n";

if (@new_notes > 1) {
    # Удаляем одну заметку для демонстрации
    my $note_to_delete = pop @new_notes;
    my $note_id = $note_to_delete->{id};
    
    print "   Удаление заметки #$note_id:\n";
    print "   📋 Заметка: '$note_to_delete->{title}'\n";
    
    my $delete_result = api_request('DELETE', "/api/notes/$note_id");
    if ($delete_result && $delete_result->{success}) {
        print "      ✅ Заметка удалена\n";
    } else {
        print "      ❌ Ошибка удаления (код: " . ($delete_result->{code} || 'unknown') . ")\n";
        if ($delete_result->{code} && $delete_result->{code} == 404) {
            print "      💡 DELETE операция может быть не реализована\n";
        }
    }
    
    # Проверяем удаление
    print "   Проверка удаления:\n";
    my $check_deleted = api_request('GET', "/api/notes/$note_id");
    if ($check_deleted && $check_deleted->{error}) {
        print "      ✅ Заметка действительно удалена\n";
    } else {
        print "      ℹ️  Заметка все еще доступна\n";
    }
} else {
    print "   ⚠️  Недостаточно заметок для демонстрации удаления\n";
}

print "\n";

# === ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ ===

print "🔧 ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ:\n";

# Поиск заметок
print "   🔍 Поиск заметок по содержанию:\n";
my $search_terms = ['API', 'demo', 'technical'];

foreach my $term (@search_terms) {
    print "      🔎 Поиск '$term':\n";
    
    # Эмуляция поиска через получение всех заметок и фильтрацию
    my $all_notes_for_search = api_request('GET', '/api/notes');
    if ($all_notes_for_search && ref($all_notes_for_search) eq 'ARRAY') {
        my @found_notes = grep { 
            ($_->{title} && $_->{title} =~ /\Q$term\E/i) || 
            ($_->{content} && $_->{content} =~ /\Q$term\E/i) ||
            ($_->{tags} && ref($_->{tags}) eq 'ARRAY' && grep { /\Q$term\E/i } @{$_->{tags}})
        } @$all_notes_for_search;
        
        print "         📋 Найдено: " . scalar(@found_notes) . " заметок\n";
        foreach my $note (@found_notes) {
            print "            📝 $note->{title} (ID: $note->{id})\n";
        }
    }
}

# Статистика по тегам
print "\n   📊 Анализ тегов:\n";
my $notes_for_tags = api_request('GET', '/api/notes');
if ($notes_for_tags && ref($notes_for_tags) eq 'ARRAY') {
    my %tag_count;
    
    foreach my $note (@$notes_for_tags) {
        if ($note->{tags} && ref($note->{tags}) eq 'ARRAY') {
            foreach my $tag (@{$note->{tags}}) {
                $tag_count{$tag}++;
            }
        }
    }
    
    if (%tag_count) {
        print "      🏷️  Популярные теги:\n";
        foreach my $tag (sort { $tag_count{$b} <=> $tag_count{$a} } keys %tag_count) {
            print "         #$tag: $tag_count{$tag} заметок\n";
        }
    } else {
        print "      📋 Теги не найдены\n";
    }
}

# Экспорт заметок
print "\n   📤 Экспорт заметок в текстовый формат:\n";
my $export_notes = api_request('GET', '/api/notes');
if ($export_notes && ref($export_notes) eq 'ARRAY') {
    my $export_file = "notes_export_" . time() . ".txt";
    
    open my $fh, '>:encoding(UTF-8)', $export_file or die "Не удалось создать файл: $!";
    
    print $fh "ЭКСПОРТ ЗАМЕТОК MEGACHAT\n";
    print $fh "=" x 40 . "\n";
    print $fh "Дата экспорта: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
    print $fh "Всего заметок: " . scalar(@$export_notes) . "\n\n";
    
    foreach my $note (@$export_notes) {
        print $fh "-" x 40 . "\n";
        print $fh "ID: $note->{id}\n";
        print $fh "ЗАГОЛОВОК: $note->{title}\n";
        print $fh "АВТОР: " . ($note->{username} || 'неизвестно') . "\n";
        print $fh "ДАТА: " . ($note->{created_at} || 'неизвестно') . "\n";
        if ($note->{tags} && @{$note->{tags}}) {
            print $fh "ТЕГИ: " . join(', ', @{$note->{tags}}) . "\n";
        }
        print $fh "\nСОДЕРЖАНИЕ:\n";
        print $fh $note->{content} . "\n\n";
    }
    
    close $fh;
    print "      ✅ Заметки экспортированы в $export_file\n";
}

print "\n";

# === ИТОГОВАЯ СТАТИСТИКА ===

print "📊 ИТОГОВАЯ СТАТИСТИКА:\n";
print "=" x 30 . "\n";

my $final_notes = api_request('GET', '/api/notes');
if ($final_notes && ref($final_notes) eq 'ARRAY') {
    my $total_notes = scalar(@$final_notes);
    my @my_notes = grep { $_->{user_id} && $_->{user_id} == $user->{id} } @$final_notes;
    my $my_notes_count = scalar(@my_notes);
    
    print "   📈 Всего заметок в системе: $total_notes\n";
    print "   👤 Ваших заметок: $my_notes_count\n";
    print "   ➕ Создано в этой сессии: " . scalar(@new_notes) . "\n";
    
    # Статистика по размеру
    my $total_chars = 0;
    my $avg_chars = 0;
    foreach my $note (@$final_notes) {
        $total_chars += length($note->{content} || '');
    }
    $avg_chars = $total_notes > 0 ? int($total_chars / $total_notes) : 0;
    
    print "   📝 Общий объем: $total_chars символов\n";
    print "   📊 Средний размер заметки: $avg_chars символов\n";
    
    if (@my_notes) {
        print "\n   📋 Ваши заметки:\n";
        foreach my $note (@my_notes) {
            my $size = length($note->{content} || '');
            print "      📝 $note->{title} ($size символов)\n";
        }
    }
}

print "\n💡 РЕКОМЕНДАЦИИ ДЛЯ РАЗРАБОТКИ:\n";
print "   🔍 Реализуйте полнотекстовый поиск\n";
print "   🏷️  Добавьте систему категорий/папок\n";
print "   📎 Поддержка прикрепления файлов\n";
print "   📊 Реализуйте сортировку и фильтрацию\n";
print "   🔄 Добавьте версионность заметок\n";
print "   🌟 Система избранных заметок\n";
print "   📤 Экспорт в различные форматы\n";
print "   🔗 Связывание заметок между собой\n";

print "\n🎉 ДЕМОНСТРАЦИЯ CRUD ОПЕРАЦИЙ С ЗАМЕТКАМИ ЗАВЕРШЕНА!\n";

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите пример
    perl examples/notes_crud.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request
    HTTP::Cookies
    JSON
    Data::Dumper
    POSIX

=head1 AUTHOR

MegaChat API Examples

=cut
