#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET POST);
use HTTP::Cookies;
use JSON;
use File::Basename;
use File::Temp qw(tempfile);
use File::Path qw(make_path);
use MIME::Base64;
use Digest::MD5 qw(md5_hex);

=head1 NAME

files_crud.pl - CRUD операции с файлами через MegaChat API

=head1 DESCRIPTION

Демонстрирует полный набор операций Create, Read, Update, Delete
для работы с файлами через REST API MegaChat приложения.
Включает загрузку, скачивание, управление и анализ файлов.

=cut

# Включаем UTF-8 вывод
binmode(STDOUT, ":encoding(UTF-8)");
binmode(STDERR, ":encoding(UTF-8)");

print "📁 MEGACHAT API - CRUD ОПЕРАЦИИ С ФАЙЛАМИ\n";
print "=" x 50 . "\n\n";

# Настройки
my $base_url = 'http://localhost:3000';
my $timeout = 60; # Увеличиваем для загрузки файлов

# HTTP клиент с поддержкой cookies
my $ua = LWP::UserAgent->new(
    timeout => $timeout,
    agent => 'MegaChat-Files-Example/1.0',
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
        if (ref($data) eq 'HASH') {
            $req->header('Content-Type' => 'application/json');
            $req->content($json->encode($data));
        } else {
            $req->content($data) if $data;
        }
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
            return { 
                success => 1, 
                content => $response->content,
                headers => $response->headers,
                size => length($response->content || '')
            };
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

sub create_sample_files {
    my @files;
    
    # Создаем временную директорию
    my $temp_dir = File::Temp->newdir(CLEANUP => 1);
    my $temp_path = $temp_dir->dirname;
    
    # 1. Текстовый файл
    my $text_file = "$temp_path/sample_document.txt";
    open my $fh1, '>:encoding(UTF-8)', $text_file or die $!;
    print $fh1 "Демонстрационный текстовый документ\n";
    print $fh1 "=====================================\n\n";
    print $fh1 "Это примерный файл для тестирования API загрузки файлов.\n\n";
    print $fh1 "Содержание:\n";
    print $fh1 "- Русский текст в UTF-8 кодировке\n";
    print $fh1 "- Множественные строки\n";
    print $fh1 "- Специальные символы: @#\$%^&*()\n";
    print $fh1 "- Эмодзи: 📁📝💾🚀\n\n";
    print $fh1 "Создан: " . localtime() . "\n";
    close $fh1;
    
    push @files, {
        path => $text_file,
        name => 'sample_document.txt',
        type => 'text/plain',
        description => 'Демонстрационный текстовый документ'
    };
    
    # 2. JSON файл
    my $json_file = "$temp_path/api_config.json";
    open my $fh2, '>:encoding(UTF-8)', $json_file or die $!;
    my $config_data = {
        api_version => "1.0",
        endpoints => {
            files => "/api/files",
            upload => "/api/files/upload",
            download => "/api/files/download"
        },
        settings => {
            max_file_size => "10MB",
            allowed_types => ["image/*", "text/*", "application/pdf"],
            upload_timeout => 60
        },
        metadata => {
            created_by => "API Demo Script",
            purpose => "Testing file operations",
            timestamp => time()
        }
    };
    print $fh2 $json->encode($config_data);
    close $fh2;
    
    push @files, {
        path => $json_file,
        name => 'api_config.json',
        type => 'application/json',
        description => 'Конфигурационный файл API'
    };
    
    # 3. CSV файл с данными
    my $csv_file = "$temp_path/users_data.csv";
    open my $fh3, '>:encoding(UTF-8)', $csv_file or die $!;
    print $fh3 "id,username,email,status,created_at\n";
    print $fh3 "1,admin,admin\@megachat.local,online,2024-01-01\n";
    print $fh3 "2,user1,user1\@megachat.local,offline,2024-01-02\n";
    print $fh3 "3,user2,user2\@megachat.local,offline,2024-01-03\n";
    print $fh3 "4,guest,guest\@megachat.local,away,2024-01-04\n";
    close $fh3;
    
    push @files, {
        path => $csv_file,
        name => 'users_data.csv',
        type => 'text/csv',
        description => 'Данные пользователей в CSV формате'
    };
    
    # 4. Малый бинарный файл (имитируем изображение)
    my $binary_file = "$temp_path/test_image.dat";
    open my $fh4, '>:raw', $binary_file or die $!;
    # Создаем псевдо-бинарные данные
    for (1..1000) {
        print $fh4 pack('C', int(rand(256)));
    }
    close $fh4;
    
    push @files, {
        path => $binary_file,
        name => 'test_image.dat',
        type => 'application/octet-stream',
        description => 'Тестовый бинарный файл'
    };
    
    return @files;
}

sub upload_file {
    my ($file_info, $conversation_id) = @_;
    
    my $file_path = $file_info->{path};
    my $file_name = $file_info->{name};
    
    print "      📤 Загрузка '$file_name':\n";
    
    # Читаем файл
    open my $fh, '<:raw', $file_path or do {
        print "         ❌ Не удалось прочитать файл: $!\n";
        return undef;
    };
    my $file_content = do { local $/; <$fh> };
    close $fh;
    
    my $file_size = length($file_content);
    print "         📊 Размер: $file_size байт\n";
    
    # Отправляем как сообщение с файлом (имитация multipart/form-data)
    my $boundary = "----MegaChatFormBoundary" . time();
    my $content = '';
    
    # Добавляем поля формы
    $content .= "--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"conversation_id\"\r\n\r\n";
    $content .= "$conversation_id\r\n";
    
    $content .= "--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"message_type\"\r\n\r\n";
    $content .= "file\r\n";
    
    # Добавляем файл
    $content .= "--$boundary\r\n";
    $content .= "Content-Disposition: form-data; name=\"file\"; filename=\"$file_name\"\r\n";
    $content .= "Content-Type: $file_info->{type}\r\n\r\n";
    $content .= $file_content;
    $content .= "\r\n--$boundary--\r\n";
    
    # Отправляем запрос
    my $req = HTTP::Request->new('POST', "$base_url/api/messages");
    $req->header('Content-Type' => "multipart/form-data; boundary=$boundary");
    $req->content($content);
    
    my $response = $ua->request($req);
    
    if ($response->is_success) {
        print "         ✅ Файл загружен успешно\n";
        
        # Пытаемся парсить ответ
        if ($response->header('Content-Type') && $response->header('Content-Type') =~ /json/) {
            my $result = eval { $json->decode($response->content) };
            if ($result && $result->{success}) {
                print "         📋 ID сообщения: $result->{id}\n";
                if ($result->{file_path}) {
                    print "         📂 Путь файла: $result->{file_path}\n";
                }
                return $result;
            }
        }
        
        return { success => 1, file_name => $file_name };
    } else {
        print "         ❌ Ошибка загрузки: " . $response->status_line . "\n";
        return undef;
    }
}

sub print_file_info {
    my ($file, $prefix) = @_;
    $prefix //= '';
    
    if (ref($file) eq 'HASH') {
        print "${prefix}📄 Файл: $file->{file_name}\n" if $file->{file_name};
        print "${prefix}   💾 Размер: " . ($file->{file_size} || 'неизвестно') . " байт\n";
        print "${prefix}   📅 Загружен: " . ($file->{created_at} || 'неизвестно') . "\n";
        print "${prefix}   👤 Автор: " . ($file->{username} || $file->{user_id} || 'неизвестно') . "\n";
        print "${prefix}   📂 Путь: " . ($file->{file_path} || 'неизвестно') . "\n";
        print "${prefix}   🏷️  Тип: " . ($file->{message_type} || 'file') . "\n";
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

# Авторизация
my $user = login_user('admin', 'admin');
if (!$user) {
    print "❌ Не удалось авторизоваться. Проверьте учетные данные.\n";
    exit 1;
}

# Получаем список чатов для загрузки файлов
print "📋 ПОЛУЧЕНИЕ СПИСКА ЧАТОВ ДЛЯ ЗАГРУЗКИ ФАЙЛОВ:\n";
my $chats = api_request('GET', '/api/conversations');
my $target_chat_id;

if ($chats && ref($chats) eq 'ARRAY' && @$chats) {
    $target_chat_id = $chats->[0]->{id};
    print "   ✅ Выбран чат: '$chats->[0]->{name}' (ID: $target_chat_id)\n";
} else {
    print "   ⚠️  Чаты не найдены, создаем тестовый чат...\n";
    
    my $new_chat = api_request('POST', '/api/conversations', {
        name => "File Testing Chat " . time(),
        description => "Чат для тестирования файловых операций",
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

# === CREATE - ЗАГРУЗКА ФАЙЛОВ ===

print "📤 CREATE - ЗАГРУЗКА ФАЙЛОВ:\n";

my @sample_files = create_sample_files();
my @uploaded_files;

print "   📁 Создано демонстрационных файлов: " . scalar(@sample_files) . "\n\n";

foreach my $file (@sample_files) {
    print "   📄 Файл: $file->{name}\n";
    print "      📋 Описание: $file->{description}\n";
    print "      🏷️  MIME-тип: $file->{type}\n";
    
    my $upload_result = upload_file($file, $target_chat_id);
    if ($upload_result) {
        push @uploaded_files, { %$upload_result, original => $file };
        print "      ✅ Загружен успешно\n";
    } else {
        print "      ❌ Ошибка загрузки\n";
    }
    print "\n";
}

# === READ - ПОЛУЧЕНИЕ СПИСКА ФАЙЛОВ ===

print "📖 READ - ПОЛУЧЕНИЕ СООБЩЕНИЙ С ФАЙЛАМИ:\n";

my $messages = api_request('GET', "/api/conversations/$target_chat_id/messages");
if ($messages && ref($messages) eq 'ARRAY') {
    my @file_messages = grep { $_->{message_type} && $_->{message_type} eq 'file' } @$messages;
    
    print "   📊 Всего сообщений: " . scalar(@$messages) . "\n";
    print "   📁 Сообщений с файлами: " . scalar(@file_messages) . "\n\n";
    
    if (@file_messages) {
        foreach my $msg (@file_messages) {
            print_file_info($msg, "   ");
            print "\n";
        }
    }
} else {
    print "   ❌ Ошибка получения сообщений\n\n";
}

# === READ - СКАЧИВАНИЕ ФАЙЛОВ ===

print "📥 READ - СКАЧИВАНИЕ ФАЙЛОВ:\n";

if (@uploaded_files) {
    print "   🔍 Попытка скачивания загруженных файлов:\n\n";
    
    foreach my $uploaded (@uploaded_files) {
        my $file_name = $uploaded->{file_name} || $uploaded->{original}->{name};
        print "   📄 Скачивание '$file_name':\n";
        
        # Пробуем различные URL для скачивания
        my @download_urls = (
            "/api/files/download/$file_name",
            "/api/files/$file_name",
            "/static/uploads/$file_name"
        );
        
        my $downloaded = 0;
        foreach my $url (@download_urls) {
            print "      🔗 Пробуем: $url\n";
            
            my $download_result = api_request('GET', $url);
            if ($download_result && !$download_result->{error}) {
                print "      ✅ Файл скачан: " . ($download_result->{size} || 0) . " байт\n";
                
                # Сохраняем в временный файл для проверки
                my ($fh, $temp_filename) = tempfile(SUFFIX => "_downloaded");
                binmode($fh, ':raw');
                print $fh $download_result->{content};
                close $fh;
                
                my $downloaded_size = -s $temp_filename;
                print "      💾 Сохранен как: $temp_filename ($downloaded_size байт)\n";
                
                # Проверяем MD5 если возможно
                if ($uploaded->{original}->{path} && -f $uploaded->{original}->{path}) {
                    my $original_md5 = get_file_md5($uploaded->{original}->{path});
                    my $downloaded_md5 = get_file_md5($temp_filename);
                    
                    if ($original_md5 eq $downloaded_md5) {
                        print "      ✅ MD5 совпадает: файл загружен корректно\n";
                    } else {
                        print "      ⚠️  MD5 не совпадает (возможна ошибка)\n";
                        print "         Оригинал: $original_md5\n";
                        print "         Скачанный: $downloaded_md5\n";
                    }
                }
                
                unlink $temp_filename;
                $downloaded = 1;
                last;
            } else {
                print "      ❌ Недоступен\n";
            }
        }
        
        if (!$downloaded) {
            print "      💡 Возможно API скачивания не реализован\n";
        }
        
        print "\n";
    }
}

# === UPDATE - ОБНОВЛЕНИЕ МЕТАДАННЫХ ФАЙЛОВ ===

print "✏️  UPDATE - ОБНОВЛЕНИЕ МЕТАДАННЫХ ФАЙЛОВ:\n";
print "   ⚠️  Примечание: Обновление файлов обычно не поддерживается\n";
print "   💡 Альтернатива: загрузка новой версии файла\n\n";

# === DELETE - УДАЛЕНИЕ ФАЙЛОВ ===

print "🗑️  DELETE - УДАЛЕНИЕ ФАЙЛОВ:\n";

if (@uploaded_files) {
    # Удаляем один файл для демонстрации
    my $file_to_delete = pop @uploaded_files;
    
    print "   🗂️  Попытка удаления файла через удаление сообщения:\n";
    print "   📄 Файл: " . ($file_to_delete->{file_name} || 'неизвестно') . "\n";
    
    if ($file_to_delete->{id}) {
        my $delete_result = api_request('DELETE', "/api/messages/$file_to_delete->{id}");
        if ($delete_result && $delete_result->{success}) {
            print "   ✅ Сообщение с файлом удалено\n";
        } else {
            print "   ❌ Ошибка удаления (код: " . ($delete_result->{code} || 'unknown') . ")\n";
            print "   💡 DELETE операция может быть не реализована\n";
        }
    } else {
        print "   ⚠️  ID сообщения не найден\n";
    }
} else {
    print "   ⚠️  Нет загруженных файлов для удаления\n";
}

print "\n";

# === ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ ===

print "🔧 ДОПОЛНИТЕЛЬНЫЕ ОПЕРАЦИИ:\n";

# Анализ типов файлов
print "   📊 Анализ загруженных файлов:\n";
if (@uploaded_files) {
    my %type_stats;
    my $total_size = 0;
    
    foreach my $file (@uploaded_files) {
        my $type = $file->{original}->{type} || 'unknown';
        $type_stats{$type}++;
        
        if ($file->{original}->{path} && -f $file->{original}->{path}) {
            $total_size += -s $file->{original}->{path};
        }
    }
    
    print "      📈 Статистика по типам:\n";
    foreach my $type (sort keys %type_stats) {
        print "         🏷️  $type: $type_stats{$type} файл(ов)\n";
    }
    print "      💾 Общий размер: $total_size байт\n";
} else {
    print "      📭 Файлы не загружены\n";
}

# Поиск файлов по расширению
print "\n   🔍 Поиск файлов по типу:\n";
my $all_messages = api_request('GET', "/api/conversations/$target_chat_id/messages");
if ($all_messages && ref($all_messages) eq 'ARRAY') {
    my %extension_count;
    
    foreach my $msg (@$all_messages) {
        if ($msg->{message_type} && $msg->{message_type} eq 'file' && $msg->{file_name}) {
            my ($name, $path, $suffix) = fileparse($msg->{file_name}, qr/\.[^.]*/);
            $suffix = lc($suffix || '.unknown');
            $extension_count{$suffix}++;
        }
    }
    
    if (%extension_count) {
        print "      📋 Файлы по расширениям:\n";
        foreach my $ext (sort keys %extension_count) {
            print "         📄 *$ext: $extension_count{$ext} файл(ов)\n";
        }
    } else {
        print "      📭 Файлы не найдены\n";
    }
}

# Проверка дискового пространства (эмуляция)
print "\n   💾 Информация о хранилище:\n";
print "      📁 Базовая директория: $base_url\n";
print "      ⚠️  Реальная проверка места требует серверного API\n";

print "\n";

# === ИТОГОВАЯ СТАТИСТИКА ===

print "📊 ИТОГОВАЯ СТАТИСТИКА:\n";
print "=" x 30 . "\n";

my $final_messages = api_request('GET', "/api/conversations/$target_chat_id/messages");
if ($final_messages && ref($final_messages) eq 'ARRAY') {
    my @final_files = grep { $_->{message_type} && $_->{message_type} eq 'file' } @$final_messages;
    
    print "   📁 Всего файлов в чате: " . scalar(@final_files) . "\n";
    print "   📤 Загружено в этой сессии: " . scalar(@uploaded_files) . "\n";
    
    if (@final_files) {
        print "\n   📋 Список файлов:\n";
        foreach my $file (@final_files) {
            my $name = $file->{file_name} || 'неизвестно';
            my $size = $file->{file_size} || '?';
            print "      📄 $name ($size байт)\n";
        }
    }
}

print "\n💡 РЕКОМЕНДАЦИИ ДЛЯ РАЗРАБОТКИ:\n";
print "   📥 Реализуйте отдельный API для скачивания файлов\n";
print "   🔍 Добавьте поиск файлов по имени и типу\n";
print "   📊 Реализуйте получение метаданных файлов\n";
print "   🗑️  Добавьте возможность удаления файлов\n";
print "   📏 Добавьте ограничения на размер и тип файлов\n";
print "   🖼️  Поддержка превью для изображений\n";
print "   📂 Организация файлов в папки/категории\n";
print "   🔒 Контроль доступа к файлам\n";
print "   💾 Мониторинг дискового пространства\n";

print "\n🎉 ДЕМОНСТРАЦИЯ CRUD ОПЕРАЦИЙ С ФАЙЛАМИ ЗАВЕРШЕНА!\n";

# Вспомогательная функция для MD5
sub get_file_md5 {
    my $file = shift;
    open my $fh, '<:raw', $file or return '';
    my $content = do { local $/; <$fh> };
    close $fh;
    return md5_hex($content);
}

__END__

=head1 USAGE

    # Убедитесь что сервер запущен
    cd megachat
    perl megachat.pl &
    
    # Запустите пример
    perl examples/files_crud.pl

=head1 DEPENDENCIES

    LWP::UserAgent
    HTTP::Request::Common
    HTTP::Cookies
    JSON
    File::Basename
    File::Temp
    File::Path
    MIME::Base64
    Digest::MD5

=head1 AUTHOR

MegaChat API Examples

=cut
