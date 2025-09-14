// Модуль для поиска
class SearchManager {
    constructor() {
        this.selectedParticipants = [];
    }

    // Поиск пользователей
    async searchUsers(query) {
        console.log('searchUsers вызвана с запросом:', query); // Отладка
        
        if (query.length < 2) {
            document.getElementById('searchResults').style.display = 'none';
            return;
        }
        
        try {
            console.log('Отправляем запрос к API...'); // Отладка
            const response = await fetch(`/api/users/search?q=${encodeURIComponent(query)}`);
            console.log('Ответ API:', response.status); // Отладка
            
            if (response.ok) {
                const users = await response.json();
                console.log('Найденные пользователи:', users); // Отладка
                this.renderSearchResults(users);
            } else {
                console.error('Ошибка API:', response.status, response.statusText);
            }
        } catch (error) {
            console.error('Ошибка поиска пользователей:', error);
        }
    }

    // Отображение результатов поиска
    renderSearchResults(users) {
        // console.log('renderSearchResults вызвана с пользователями:', users); // Отладка
        
        const container = document.getElementById('searchResultsList');
        const searchResults = document.getElementById('searchResults');
        
        // console.log('Контейнеры найдены:', { container: !!container, searchResults: !!searchResults }); // Отладка
        
        if (users.length === 0) {
            container.innerHTML = '<div class="list-group-item text-muted">Пользователи не найдены</div>';
        } else {
            container.innerHTML = users.map(user => `
                <div class="list-group-item list-group-item-action" data-user-id="${user.id}" data-username="${user.username}">
                    <div class="d-flex w-100 justify-content-between">
                        <h6 class="mb-1">${user.username}</h6>
                        <small class="text-muted">${user.status === 'online' ? '🟢' : '⚫'}</small>
                    </div>
                    <p class="mb-1 text-muted small">${user.email || 'Нет email'}</p>
                </div>
            `).join('');
        }
        
        searchResults.style.display = 'block';
        
        // Добавляем обработчики событий для участников
        const items = container.querySelectorAll('.list-group-item-action');
        items.forEach(item => {
            item.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                
                const userId = parseInt(this.getAttribute('data-user-id'));
                const username = this.getAttribute('data-username');
                console.log('🔴 КЛИК ПО УЧАСТНИКУ (search.js):', userId, username);
                searchManager.addParticipant(userId, username);
            });
        });
        
        // console.log('Результаты поиска отображены'); // Отладка
    }

    // Добавление участника
    addParticipant(userId, username) {
        console.log('🔴 addParticipant вызвана (search.js):', userId, username); // Отладка
        
        if (!this.selectedParticipants.find(p => p.id === userId)) {
            this.selectedParticipants.push({ id: userId, username: username });
            console.log('✅ Участник добавлен (search.js):', this.selectedParticipants); // Отладка
            
            // Обновляем глобальный массив участников
            if (window.selectedParticipants) {
                window.selectedParticipants = [...this.selectedParticipants];
            }
            
            this.renderSelectedParticipants();
        } else {
            console.log('⚠️ Участник уже выбран (search.js)'); // Отладка
        }
        
        document.getElementById('participantsSearch').value = '';
        document.getElementById('searchResults').style.display = 'none';
    }

    // Удаление участника
    removeParticipant(userId) {
        this.selectedParticipants = this.selectedParticipants.filter(p => p.id !== userId);
        
        // Обновляем глобальный массив участников
        if (window.selectedParticipants) {
            window.selectedParticipants = [...this.selectedParticipants];
        }
        
        this.renderSelectedParticipants();
    }

    // Отображение выбранных участников
    renderSelectedParticipants() {
        // console.log('renderSelectedParticipants вызвана с участниками:', this.selectedParticipants); // Отладка
        
        const container = document.getElementById('selectedParticipants');
        // console.log('Контейнер выбранных участников найден:', !!container); // Отладка
        
        if (this.selectedParticipants.length === 0) {
            container.innerHTML = '<div class="list-group-item text-muted">Участники не выбраны</div>';
        } else {
            container.innerHTML = this.selectedParticipants.map(participant => `
                <div class="list-group-item d-flex justify-content-between align-items-center">
                    <span>${participant.username}</span>
                    <button type="button" class="btn btn-sm btn-outline-danger" data-participant-id="${participant.id}">
                        <i class="bi bi-x"></i>
                    </button>
                </div>
            `).join('');
            
            // Добавляем обработчики для кнопок удаления
            container.querySelectorAll('button[data-participant-id]').forEach(button => {
                button.addEventListener('click', function() {
                    const participantId = parseInt(this.getAttribute('data-participant-id'));
                    searchManager.removeParticipant(participantId);
                });
            });
        }
        
        // console.log('Выбранные участники отображены'); // Отладка
    }

    // Создание чата
    async createChat() {
        console.log('🔴 createChat вызвана (search.js) с участниками:', this.selectedParticipants); // Отладка
        
        if (this.selectedParticipants.length === 0) {
            alert('Выберите хотя бы одного участника');
            return;
        }
        
        const chatName = document.getElementById('chatName').value.trim();
        const chatDescription = (document.getElementById('chatDescription').value || '').trim();
        
        console.log('📝 Данные чата (search.js):', {
            name: chatName,
            description: chatDescription,
            participants: this.selectedParticipants.map(p => p.id)
        });
        
        try {
            const response = await fetch('/api/conversations', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    name: chatName || 'Новый чат',
                    description: chatDescription,
                    participants: this.selectedParticipants.map(p => p.id)
                })
            });
            
            console.log('📡 Ответ API (search.js):', response.status);
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            const data = await response.json();
            console.log('✅ Чат создан (search.js):', data);
            
            if (data.success) {
                bootstrap.Modal.getInstance(document.getElementById('newChatModal')).hide();
                document.getElementById('newChatForm').reset();
                this.selectedParticipants = [];
                window.selectedParticipants = [];
                this.renderSelectedParticipants();
                
                console.log('🎉 Чат создан, ID:', data.id);
                
                // Обновляем список чатов
                if (window.loadConversations) {
                    await window.loadConversations();
                }
                
                // Автоматически выбираем созданный чат
                if (data.id && window.chatManager) {
                    console.log('🎯 Автовыбор созданного чата:', data.id);
                    await chatManager.selectConversation(data.id);
                } else {
                    alert('Чат успешно создан!');
                }
            } else {
                alert(data.error || 'Ошибка создания чата');
            }
        } catch (error) {
            console.error('❌ Ошибка создания чата (search.js):', error);
            alert('Ошибка при создании чата: ' + error.message);
        }
    }

    // Поиск сообщений
    async searchMessages() {
        const query = document.getElementById('messageSearch').value.trim();
        if (!query) {
            uiManager.showError('Введите поисковый запрос');
            return;
        }
        
        const searchText = document.getElementById('searchText').checked;
        const searchFiles = document.getElementById('searchFiles').checked;
        const searchNotes = document.getElementById('searchNotes').checked;
        
        if (!searchText && !searchFiles && !searchNotes) {
            uiManager.showError('Выберите хотя бы один тип поиска');
            return;
        }
        
        try {
            const response = await fetch('/api/messages/search', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    query: query,
                    search_text: searchText,
                    search_files: searchFiles,
                    search_notes: searchNotes
                })
            });
            
            if (response.ok) {
                const results = await response.json();
                this.showSearchResults(results);
            } else {
                uiManager.showError('Ошибка поиска');
            }
        } catch (error) {
            console.error('Ошибка поиска:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Показ результатов поиска
    showSearchResults(results) {
        console.log('🔍 Показываем результаты поиска:', results);
        const container = document.getElementById('messageSearchResults');
        const searchResults = document.getElementById('messageSearchResultsList');
        
        if (!container || !searchResults) {
            console.error('❌ Контейнеры для результатов поиска не найдены!');
            uiManager.showError('Ошибка отображения результатов поиска');
            return;
        }
        
        if (results.length === 0) {
            searchResults.innerHTML = '<div class="list-group-item text-muted">Сообщения не найдены</div>';
        } else {
            searchResults.innerHTML = results.map(result => this.formatSearchResult(result)).join('');
        }
        
        container.style.display = 'block';
        console.log('✅ Результаты поиска отображены');
        
        // Добавляем обработчики для результатов поиска сообщений
        const messageItems = searchResults.querySelectorAll('.list-group-item-action');
        messageItems.forEach(item => {
            item.addEventListener('click', function() {
                const messageId = parseInt(this.getAttribute('data-message-id'));
                const conversationId = parseInt(this.getAttribute('data-conversation-id'));
                searchManager.goToMessage(messageId, conversationId);
            });
        });
    }

    // Форматирование результата поиска
    formatSearchResult(result) {
        let content = '';
        let type = '';
        
        if (result.message_type === 'file') {
            content = `📁 ${result.file_name}`;
            type = 'Файл';
        } else if (result.message_type === 'note') {
            content = `📝 ${result.note_title}`;
            type = 'Заметка';
        } else if (result.message_type === 'image') {
            content = `🖼️ ${result.file_name}`;
            type = 'Изображение';
        } else if (result.message_type === 'voice') {
            content = `🎤 Голосовое сообщение`;
            type = 'Голосовое';
        } else {
            content = result.content;
            type = 'Текст';
        }
        
        const highlightedContent = this.highlightSearchTerm(content, document.getElementById('messageSearch').value);
        
        return `
            <div class="list-group-item list-group-item-action" data-message-id="${result.message_id}" data-conversation-id="${result.conversation_id}">
                <div class="d-flex w-100 justify-content-between">
                    <h6 class="mb-1">${result.conversation_name}</h6>
                    <small class="text-muted">${type}</small>
                </div>
                <p class="mb-1">${highlightedContent}</p>
                <small class="text-muted">От: ${result.sender_username} • ${result.created_at_formatted}</small>
            </div>
        `;
    }

    // Подсветка поискового запроса
    highlightSearchTerm(text, query) {
        if (!query) return text;
        const regex = new RegExp(`(${query})`, 'gi');
        return text.replace(regex, '<mark>$1</mark>');
    }

    // Переход к сообщению
    goToMessage(messageId, conversationId) {
        chatManager.selectConversation(conversationId);
        this.clearSearch();
        
        // Прокручиваем к сообщению
        setTimeout(() => {
            const messageElement = document.querySelector(`[oncontextmenu*="${messageId}"]`);
            if (messageElement) {
                messageElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
                messageElement.style.backgroundColor = '#fff3cd';
                setTimeout(() => {
                    messageElement.style.backgroundColor = '';
                }, 3000);
            }
        }, 500);
    }

    // Очистка поиска
    clearSearch() {
        document.getElementById('messageSearch').value = '';
        document.getElementById('searchResults').style.display = 'none';
    }
}

// Создаем глобальный экземпляр
window.searchManager = new SearchManager();
