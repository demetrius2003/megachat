// Модуль для работы с чатами
class ChatManager {
    constructor() {
        this.conversations = [];
        this.currentConversationId = null;
        this.currentUserId = null;
        this.lastMessageId = 0;
        this.selectedParticipants = [];
    }

    // Загрузка списка чатов
    async loadConversations() {
        try {
            const response = await fetch('/api/conversations');
            if (response.ok) {
                this.conversations = await response.json();
                console.log('📋 Загружено чатов:', this.conversations.length);
                this.renderConversations();
            } else {
                this.showError('Ошибка загрузки чатов');
            }
        } catch (error) {
            console.error('Ошибка загрузки чатов:', error);
            this.showError('Ошибка соединения');
        }
    }

    // Отображение списка чатов
    renderConversations() {
        const container = document.getElementById('conversationsList');
        const emptyState = document.getElementById('emptyConversations');
        
        if (this.conversations.length === 0) {
            container.innerHTML = '';
            emptyState.style.display = 'block';
            return;
        }
        
        emptyState.style.display = 'none';
        container.innerHTML = this.conversations.map(conv => {
            let icon = 'bi-chat-dots';
            if (conv.type === 'notes') icon = 'bi-journal-text';
            else if (conv.type === 'files') icon = 'bi-cloud-upload';
            else if (conv.type === 'group') icon = 'bi-people';
            
            return `
                <a href="#" class="list-group-item list-group-item-action ${conv.id === this.currentConversationId ? 'active' : ''}" 
                   data-conversation-id="${conv.id}">
                    <div class="d-flex w-100 justify-content-between">
                        <h6 class="mb-1">
                            <i class="bi ${icon}"></i> ${conv.name || 'Личный чат'}
                        </h6>
                        <small>${conv.updated_at_formatted}</small>
                    </div>
                    <p class="mb-1 text-muted small">${conv.last_message || 'Нет сообщений'}</p>
                    <small>${conv.last_message_sender_username ? 'От: ' + conv.last_message_sender_username : ''}</small>
                </a>
            `;
        }).join('');
        
        // Добавляем обработчики кликов после рендеринга
        this.setupConversationClickHandlers();
    }
    
    // Настройка обработчиков кликов по чатам
    setupConversationClickHandlers() {
        const container = document.getElementById('conversationsList');
        if (!container) return;
        
        // Удаляем предыдущие обработчики
        container.removeEventListener('click', this.handleConversationClick);
        
        // Добавляем новый обработчик
        this.handleConversationClick = (e) => {
            e.preventDefault();
            const listItem = e.target.closest('.list-group-item[data-conversation-id]');
            if (listItem) {
                const conversationId = parseInt(listItem.getAttribute('data-conversation-id'));
                console.log('🎯 Клик по чату:', conversationId);
                this.selectConversation(conversationId);
            }
        };
        
        container.addEventListener('click', this.handleConversationClick);
    }

    // Выбор чата
    async selectConversation(conversationId) {
        console.log('🎯 Выбираем чат:', conversationId);
        
        // Покидаем предыдущий чат
        if (this.currentConversationId) {
            websocketManager.leaveConversation();
        }
        
        this.currentConversationId = conversationId;
        this.lastMessageId = 0;
        
        // Обновляем активный элемент в списке
        document.querySelectorAll('#conversationsList .list-group-item').forEach(item => {
            item.classList.remove('active');
        });
        
        // Находим и активируем элемент чата
        const chatElement = document.querySelector(`#conversationsList .list-group-item[data-conversation-id="${conversationId}"]`);
        if (chatElement) {
            chatElement.classList.add('active');
            console.log('✅ Чат активирован в списке');
        } else {
            console.warn('⚠️ Элемент чата не найден в списке');
        }
        
        // Показываем область чата
        document.getElementById('chatArea').style.display = 'block';
        
        // Загружаем информацию о чате
        console.log('🔄 Загружаем информацию о чате:', conversationId);
        await this.loadChatInfo(conversationId);
        
        // Загружаем сообщения
        await this.loadMessages(conversationId);
        
        // Показываем/скрываем панель ввода в зависимости от типа чата
        const currentChat = this.conversations.find(c => c.id === conversationId);
        const messageForm = document.querySelector('#chatArea .card-footer');
        
        if (currentChat && (currentChat.type === 'notes' || currentChat.type === 'files')) {
            messageForm.style.display = 'none';
        } else {
            messageForm.style.display = 'block';
        }
        
        // Присоединяемся к чату через WebSocket
        if (!currentChat || (currentChat.type !== 'notes' && currentChat.type !== 'files')) {
            websocketManager.joinConversation(conversationId);
            pollingManager.startPolling(); // Fallback поллинг
        } else {
            pollingManager.stopPolling();
        }
    }

    // Загрузка информации о чате
    async loadChatInfo(conversationId) {
        console.log('🏷️ loadChatInfo вызвана для чата:', conversationId);
        try {
            const response = await fetch(`/api/conversations/${conversationId}`);
            console.log('📡 Ответ API /api/conversations/' + conversationId + ':', response.status);
            if (response.ok) {
                const chat = await response.json();
                
                // Обновляем название чата
                let chatTitle = chat.name || 'Личный чат';
                if (chat.type === 'notes') {
                    chatTitle = '📝 Избранные заметки';
                } else if (chat.type === 'files') {
                    chatTitle = '📁 Избранные файлы';
                }
                const titleElement = document.getElementById('chatTitle');
                const descElement = document.getElementById('chatDescription');
                
                if (titleElement) {
                    titleElement.textContent = chatTitle;
                    console.log('✅ Заголовок установлен:', chatTitle);
                } else {
                    console.error('❌ Элемент chatTitle не найден!');
                }
                
                // Обновляем описание с участниками
                let description = '';
                if (chat.participants && chat.participants.length > 0) {
                    const participantNames = chat.participants.map(p => p.username).join(', ');
                    description = `Участники: ${participantNames}`;
                } else if (chat.description) {
                    description = chat.description;
                } else {
                    description = chat.type === 'notes' ? 'Ваши сохраненные заметки' : 
                                 chat.type === 'files' ? 'Ваши сохраненные файлы' : 
                                 'Нет описания';
                }
                
                if (descElement) {
                    descElement.textContent = description;
                    console.log('✅ Описание установлено:', description);
                } else {
                    console.error('❌ Элемент chatDescription не найден!');
                }
                
                console.log('🏷️ Заголовок чата обновлен:', chatTitle, '|', description);
            } else if (response.status === 404) {
                console.warn('⚠️ Чат недоступен, показываем сообщение об ошибке');
                
                // Показываем сообщение пользователю
                const titleElement = document.getElementById('chatTitle');
                const descElement = document.getElementById('chatDescription');
                
                if (titleElement) titleElement.textContent = '❌ Чат недоступен';
                if (descElement) descElement.textContent = 'Этот чат был удален или у вас нет к нему доступа';
                
                // Очищаем область сообщений
                const messagesList = document.getElementById('messagesList');
                if (messagesList) {
                    messagesList.innerHTML = '<div class="alert alert-warning">Чат недоступен</div>';
                }
            } else {
                console.error('❌ Ошибка загрузки чата:', response.status);
                const titleElement = document.getElementById('chatTitle');
                const descElement = document.getElementById('chatDescription');
                
                if (titleElement) titleElement.textContent = '⚠️ Ошибка загрузки';
                if (descElement) descElement.textContent = 'Не удалось загрузить информацию о чате';
            }
        } catch (error) {
            console.error('Ошибка загрузки информации о чате:', error);
            const titleElement = document.getElementById('chatTitle');
            const descElement = document.getElementById('chatDescription');
            
            if (titleElement) titleElement.textContent = '⚠️ Ошибка соединения';
            if (descElement) descElement.textContent = 'Проблема с подключением к серверу';
        }
    }

    // Загрузка сообщений
    async loadMessages(conversationId) {
        try {
            const currentChat = this.conversations.find(c => c.id === conversationId);
            
            // Если это специальный чат, не загружаем сообщения
            if (currentChat && (currentChat.type === 'notes' || currentChat.type === 'files')) {
                if (currentChat.type === 'notes') {
                    await this.renderNotesInChat();
                } else if (currentChat.type === 'files') {
                    await this.renderFilesInChat();
                }
                return;
            }
            
            const response = await fetch(`/api/conversations/${conversationId}/messages`);
            if (response.ok) {
                const messages = await response.json();
                this.renderMessages(messages);
                this.lastMessageId = messages.length > 0 ? messages[messages.length - 1].id : 0;
                this.scrollToBottom();
            } else {
                console.error('Ошибка загрузки сообщений:', error);
            }
        } catch (error) {
            console.error('Ошибка загрузки сообщений:', error);
        }
    }

    // Отображение сообщений
    renderMessages(messages) {
        const container = document.getElementById('messagesList');
        
        if (messages.length === 0) {
            container.innerHTML = '<div class="text-center text-muted">Нет сообщений</div>';
            return;
        }
        
        container.innerHTML = messages.map((message, index) => {
            let messageHtml = '';
            let messageClass = 'message-card';
            
            if (message.message_type === 'file') {
                messageClass += ' message-file';
                messageHtml = `
                    <div class="d-flex align-items-center">
                        <i class="bi bi-file-earmark me-2"></i>
                        <div class="flex-grow-1">
                            <strong>${message.file_name}</strong>
                            <small class="text-muted d-block">${message.file_size_formatted}</small>
                        </div>
                        <a href="/download/${message.stored_name}" class="btn btn-sm btn-outline-primary" target="_blank">
                            <i class="bi bi-download"></i>
                        </a>
                    </div>
                `;
            } else if (message.message_type === 'note') {
                messageClass += ' message-note';
                messageHtml = `
                    <div class="d-flex align-items-start">
                        <i class="bi bi-journal-text me-2"></i>
                        <div class="flex-grow-1">
                            <strong style="color: ${message.note_color}">${message.note_title}</strong>
                            <div class="text-muted small">${message.note_content}</div>
                        </div>
                    </div>
                `;
            } else if (message.message_type === 'image') {
                messageClass += ' message-image';
                messageHtml = `
                    <div class="image-message">
                        <div class="d-flex align-items-center mb-2">
                            <i class="bi bi-image me-2"></i>
                            <div class="flex-grow-1">
                                <strong>${message.file_name}</strong>
                                <small class="text-muted d-block">${message.file_size_formatted}</small>
                            </div>
                            <a href="/download/${message.stored_name}" class="btn btn-sm btn-outline-primary" target="_blank">
                                <i class="bi bi-eye"></i>
                            </a>
                        </div>
                        <div class="image-preview-container">
                            <img src="/download/${message.stored_name}" 
                                 class="img-fluid rounded" 
                                 style="max-width: 300px; max-height: 200px; cursor: pointer;"
                                 onclick="uiManager.showImageModal('${message.stored_name}', '${message.file_name}')"
                                 onerror="this.style.display='none'">
                        </div>
                    </div>
                `;
            } else if (message.message_type === 'voice') {
                messageClass += ' message-voice';
                messageHtml = `
                    <div class="voice-message">
                        <div class="voice-controls">
                            <button class="btn btn-sm btn-outline-primary" onclick="voiceManager.playVoiceMessage('${message.stored_name}')">
                                <i class="bi bi-play-circle"></i>
                            </button>
                            <div class="voice-waveform"></div>
                            <span class="voice-duration">0:00</span>
                        </div>
                        <div class="mt-2">
                            <small class="text-muted">
                                <i class="bi bi-mic"></i> Голосовое сообщение
                            </small>
                        </div>
                    </div>
                `;
            } else {
                messageHtml = message.content;
            }
            
            const isCurrentUser = message.sender_id === this.currentUserId;
            // Диагностика для первых 3 сообщений
            if (index < 3) {
                console.log(`💬 Сообщение ${index}: sender_id=${message.sender_id}, currentUserId=${this.currentUserId}, isCurrentUser=${isCurrentUser}, username=${message.sender_username}`);
            }
            return `
                <div class="${messageClass} ${isCurrentUser ? 'text-end' : 'text-start'}">
                    <div class="message-container position-relative" 
                         oncontextmenu="uiManager.showMessageContextMenu(event, ${message.id}, ${isCurrentUser})">
                        <div class="small text-muted mb-1">${message.sender_username}</div>
                        <div>${messageHtml}</div>
                        <div class="small text-muted mt-1">${message.created_at_formatted}</div>
                        
                        <!-- Реакции -->
                        <div class="message-reactions mt-2" id="reactions-${message.id}">
                            <!-- Реакции будут загружены здесь -->
                        </div>
                        
                        <!-- Кнопка добавления реакции -->
                        <div class="reaction-btn" onclick="reactionManager.showReactionPicker(${message.id})" style="opacity: 0.5; cursor: pointer;">
                            <i class="bi bi-emoji-smile"></i>
                        </div>
                    </div>
                </div>
            `;
        }).join('');
        
        // Загружаем реакции для всех сообщений
        messages.forEach(message => {
            reactionManager.loadReactions(message.id);
        });
        
        // Применяем стили сообщений после рендеринга
        setTimeout(() => {
            if (window.applyMessageStyles) {
                window.applyMessageStyles();
            }
        }, 100);
    }

    // Прокрутка вниз
    scrollToBottom() {
        const container = document.getElementById('messagesContainer');
        container.scrollTop = container.scrollHeight;
    }

    // Отображение заметок в чате
    async renderNotesInChat() {
        const container = document.getElementById('messagesList');
        
        try {
            const response = await fetch('/api/notes');
            if (response.ok) {
                const notes = await response.json();
                
                if (notes.length === 0) {
                    container.innerHTML = '<div class="alert alert-info">Нет заметок</div>';
                    return;
                }
                
                container.innerHTML = notes.map(note => `
                    <div class="card mb-3">
                        <div class="card-body">
                            <div class="d-flex justify-content-between align-items-start">
                                <h6 class="card-title" style="color: ${note.color}">${note.title}</h6>
                                <div class="btn-group btn-group-sm">
                                    <button class="btn btn-outline-primary" onclick="noteManager.loadNoteForEdit(${note.id})">
                                        <i class="bi bi-pencil"></i>
                                    </button>
                                    <button class="btn btn-outline-success" onclick="noteManager.shareNote(${note.id})">
                                        <i class="bi bi-share"></i>
                                    </button>
                                    <button class="btn btn-outline-danger" onclick="noteManager.deleteNote(${note.id})">
                                        <i class="bi bi-trash"></i>
                                    </button>
                                </div>
                            </div>
                            <p class="card-text">${note.content}</p>
                            <small class="text-muted">Создано: ${note.created_at_formatted}</small>
                        </div>
                    </div>
                `).join('');
            } else {
                container.innerHTML = '<div class="alert alert-danger">Ошибка загрузки заметок</div>';
            }
        } catch (error) {
            container.innerHTML = '<div class="alert alert-danger">Ошибка соединения</div>';
        }
    }

    // Отображение файлов в чате
    async renderFilesInChat() {
        const container = document.getElementById('messagesList');
        
        try {
            const response = await fetch('/api/files');
            if (response.ok) {
                const files = await response.json();
                
                if (files.length === 0) {
                    container.innerHTML = '<div class="alert alert-info">Нет файлов</div>';
                    return;
                }
                
                container.innerHTML = files.map(file => `
                    <div class="card mb-3">
                        <div class="card-body">
                            <div class="d-flex justify-content-between align-items-start">
                                <div>
                                    <h6 class="card-title">${file.original_name}</h6>
                                    <p class="card-text text-muted small">
                                        Размер: ${file.file_size_formatted}<br>
                                        GUID: ${file.stored_name}
                                    </p>
                                    <small class="text-muted">Загружен: ${file.created_at_formatted}</small>
                                </div>
                                <div class="btn-group btn-group-sm">
                                    <button class="btn btn-outline-primary" onclick="fileManager.downloadFile('${file.stored_name}')">
                                        <i class="bi bi-download"></i>
                                    </button>
                                    <button class="btn btn-outline-success" onclick="fileManager.shareFile(${file.id})">
                                        <i class="bi bi-share"></i>
                                    </button>
                                    <button class="btn btn-outline-danger" onclick="fileManager.deleteFile(${file.id})">
                                        <i class="bi bi-trash"></i>
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                `).join('');
            } else {
                container.innerHTML = '<div class="alert alert-danger">Ошибка загрузки файлов</div>';
            }
        } catch (error) {
            container.innerHTML = '<div class="alert alert-danger">Ошибка соединения</div>';
        }
    }

    // Отправка сообщения
    async sendMessage() {
        const input = document.getElementById('messageInput');
        const content = input.value.trim();
        
        if (!content || !this.currentConversationId) return;
        
        input.value = '';
        
        try {
            const response = await fetch(`/api/conversations/${this.currentConversationId}/messages`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ content })
            });
            
            if (response.ok) {
                // Обновляем список чатов
                await this.loadConversations();
                // Перезагружаем сообщения в текущем чате
                await this.loadMessages(this.currentConversationId);
                // Применяем стили сообщений
                if (window.applyMessageStyles) {
                    setTimeout(() => window.applyMessageStyles(), 100);
                }
            } else {
                this.showError('Ошибка отправки сообщения');
            }
        } catch (error) {
            this.showError('Ошибка соединения');
        }
    }

    // Добавление нового сообщения в чат (для WebSocket)
    addMessageToChat(message) {
        const container = document.getElementById('messagesList');
        
        // Создаем HTML для сообщения
        let messageHtml = '';
        let messageClass = 'message-card';
        
        if (message.message_type === 'file') {
            messageClass += ' message-file';
            messageHtml = `
                <div class="d-flex align-items-center">
                    <i class="bi bi-file-earmark me-2"></i>
                    <div class="flex-grow-1">
                        <strong>${message.file_name}</strong>
                        <small class="text-muted d-block">${message.file_size_formatted}</small>
                    </div>
                    <a href="/download/${message.stored_name}" class="btn btn-sm btn-outline-primary" target="_blank">
                        <i class="bi bi-download"></i>
                    </a>
                </div>
            `;
        } else if (message.message_type === 'note') {
            messageClass += ' message-note';
            messageHtml = `
                <div class="d-flex align-items-start">
                    <i class="bi bi-journal-text me-2"></i>
                    <div class="flex-grow-1">
                        <strong style="color: ${message.note_color}">${message.note_title}</strong>
                        <div class="text-muted small">${message.note_content}</div>
                    </div>
                </div>
            `;
        } else if (message.message_type === 'image') {
            messageClass += ' message-image';
            messageHtml = `
                <div class="image-message">
                    <div class="d-flex align-items-center mb-2">
                        <i class="bi bi-image me-2"></i>
                        <div class="flex-grow-1">
                            <strong>${message.file_name}</strong>
                            <small class="text-muted d-block">${message.file_size_formatted}</small>
                        </div>
                        <a href="/download/${message.stored_name}" class="btn btn-sm btn-outline-primary" target="_blank">
                            <i class="bi bi-eye"></i>
                        </a>
                    </div>
                    <div class="image-preview-container">
                        <img src="/download/${message.stored_name}" 
                             class="img-fluid rounded" 
                             style="max-width: 300px; max-height: 200px; cursor: pointer;"
                             onclick="uiManager.showImageModal('${message.stored_name}', '${message.file_name}')"
                             onerror="this.style.display='none'">
                    </div>
                </div>
            `;
        } else if (message.message_type === 'voice') {
            messageClass += ' message-voice';
            messageHtml = `
                <div class="voice-message">
                    <div class="voice-controls">
                        <button class="btn btn-sm btn-outline-primary" onclick="voiceManager.playVoiceMessage('${message.stored_name}')">
                            <i class="bi bi-play-circle"></i>
                        </button>
                        <div class="voice-waveform"></div>
                        <span class="voice-duration">0:00</span>
                    </div>
                    <div class="mt-2">
                        <small class="text-muted">
                            <i class="bi bi-mic"></i> Голосовое сообщение
                        </small>
                    </div>
                </div>
            `;
        } else {
            messageHtml = message.content;
        }
        
        const isCurrentUser = message.sender_id === this.currentUserId;
        const messageElement = document.createElement('div');
        messageElement.className = `${messageClass} ${isCurrentUser ? 'text-end' : 'text-start'}`;
        messageElement.innerHTML = `
            <div class="message-container position-relative" 
                 oncontextmenu="uiManager.showMessageContextMenu(event, ${message.id}, ${isCurrentUser})">
                <div class="small text-muted mb-1">${message.sender_username}</div>
                <div>${messageHtml}</div>
                <div class="small text-muted mt-1">${message.created_at_formatted}</div>
                
                <!-- Реакции -->
                <div class="message-reactions mt-2" id="reactions-${message.id}">
                    <!-- Реакции будут загружены здесь -->
                </div>
                
                <!-- Кнопка добавления реакции -->
                <div class="reaction-btn" onclick="reactionManager.showReactionPicker(${message.id})" style="opacity: 0.5; cursor: pointer;">
                    <i class="bi bi-emoji-smile"></i>
                </div>
            </div>
        `;
        
        container.appendChild(messageElement);
        
        // Загружаем реакции
        reactionManager.loadReactions(message.id);
        
        // Прокручиваем вниз
        this.scrollToBottom();
    }

    // Показ ошибки
    showError(message) {
        // Используем UI Manager для показа ошибок
        if (window.uiManager) {
            uiManager.showError(message);
        } else {
            alert(message);
        }
    }
}

// Создаем глобальный экземпляр
window.chatManager = new ChatManager();
