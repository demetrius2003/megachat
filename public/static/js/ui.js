// Модуль для работы с пользовательским интерфейсом
class UIManager {
    constructor() {
        this.contextMenu = null;
        this.quotedMessage = null;
        this.editingMessage = null;
    }

    // Показ ошибки
    showError(message) {
        this.showToast(message, 'danger');
    }

    // Показ успеха
    showSuccess(message) {
        this.showToast(message, 'success');
    }

    // Показ уведомления
    showToast(message, type = 'info') {
        const toastContainer = this.getToastContainer();
        const toastId = 'toast-' + Date.now();
        
        const toast = document.createElement('div');
        toast.id = toastId;
        toast.className = `toast align-items-center text-white bg-${type} border-0`;
        toast.setAttribute('role', 'alert');
        toast.innerHTML = `
            <div class="d-flex">
                <div class="toast-body">${message}</div>
                <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
            </div>
        `;
        
        toastContainer.appendChild(toast);
        
        const bsToast = new bootstrap.Toast(toast);
        bsToast.show();
        
        // Удаляем toast после скрытия
        toast.addEventListener('hidden.bs.toast', () => {
            toast.remove();
        });
    }

    // Получение контейнера для toast
    getToastContainer() {
        let container = document.getElementById('toastContainer');
        if (!container) {
            container = document.createElement('div');
            container.id = 'toastContainer';
            container.className = 'toast-container position-fixed top-0 end-0 p-3';
            container.style.zIndex = '9999';
            document.body.appendChild(container);
        }
        return container;
    }

    // Показ модального окна изображения
    showImageModal(storedName, fileName) {
        const modal = document.getElementById('imageModal');
        const modalImage = document.getElementById('imageModalImage');
        const modalTitle = document.getElementById('imageModalTitle');
        const modalDownload = document.getElementById('imageModalDownload');
        
        modalTitle.textContent = fileName;
        modalImage.src = `/download/${storedName}`;
        modalDownload.href = `/download/${storedName}`;
        modalDownload.download = fileName;
        
        const bsModal = new bootstrap.Modal(modal);
        bsModal.show();
    }

    // Показ контекстного меню сообщения
    showMessageContextMenu(event, messageId, isOwnMessage) {
        event.preventDefault();
        this.hideContextMenu();
        
        this.contextMenu = document.createElement('div');
        this.contextMenu.className = 'message-context-menu';
        this.contextMenu.style.left = event.pageX + 'px';
        this.contextMenu.style.top = event.pageY + 'px';
        this.contextMenu.style.display = 'block';
        
        let menuItems = `
            <button data-message-id="${messageId}" data-action="quote">
                <i class="bi bi-quote"></i> Цитировать
            </button>
            <button data-message-id="${messageId}" data-action="copy">
                <i class="bi bi-copy"></i> Копировать
            </button>
        `;
        
        if (isOwnMessage) {
            menuItems += `
                <button data-message-id="${messageId}" data-action="edit">
                    <i class="bi bi-pencil"></i> Редактировать
                </button>
                <button data-message-id="${messageId}" data-action="delete" class="danger">
                    <i class="bi bi-trash"></i> Удалить
                </button>
            `;
        }
        
        this.contextMenu.innerHTML = menuItems;
        document.body.appendChild(this.contextMenu);
        
        // Добавляем обработчики для кнопок контекстного меню
        this.contextMenu.querySelectorAll('button').forEach(button => {
            button.addEventListener('click', function() {
                const action = this.getAttribute('data-action');
                const msgId = parseInt(this.getAttribute('data-message-id'));
                if (action === 'quote') {
                    uiManager.quoteMessage(msgId);
                } else if (action === 'copy') {
                    uiManager.copyMessage(msgId);
                } else if (action === 'edit') {
                    uiManager.editMessage(msgId);
                } else if (action === 'delete') {
                    uiManager.deleteMessage(msgId);
                }
            });
        });
        
        // Закрытие при клике вне меню
        setTimeout(() => {
            document.addEventListener('click', this.hideContextMenu.bind(this));
        }, 100);
    }

    // Скрытие контекстного меню
    hideContextMenu() {
        if (this.contextMenu) {
            this.contextMenu.remove();
            this.contextMenu = null;
        }
        document.removeEventListener('click', this.hideContextMenu.bind(this));
    }

    // Цитирование сообщения
    async quoteMessage(messageId) {
        try {
            const response = await fetch(`/api/messages/${messageId}`);
            if (response.ok) {
                const message = await response.json();
                this.quotedMessage = message;
                
                const messageInput = document.getElementById('messageInput');
                if (messageInput) {
                    messageInput.value = `> ${message.sender_username}: ${message.content || 'Файл или заметка'}\n\n`;
                    messageInput.focus();
                }
            }
        } catch (error) {
            console.error('Ошибка загрузки сообщения:', error);
        }
        this.hideContextMenu();
    }

    // Копирование сообщения
    async copyMessage(messageId) {
        try {
            const response = await fetch(`/api/messages/${messageId}`);
            if (response.ok) {
                const message = await response.json();
                const textToCopy = `${message.sender_username}: ${message.content || 'Файл или заметка'}`;
                
                try {
                    await navigator.clipboard.writeText(textToCopy);
                    this.showSuccess('Сообщение скопировано');
                } catch (error) {
                    console.error('Ошибка копирования:', error);
                    this.showError('Ошибка копирования');
                }
            }
        } catch (error) {
            console.error('Ошибка копирования:', error);
        }
        this.hideContextMenu();
    }

    // Редактирование сообщения
    async editMessage(messageId) {
        try {
            const response = await fetch(`/api/messages/${messageId}`);
            if (response.ok) {
                const message = await response.json();
                this.editingMessage = messageId;
                
                const messageContainer = document.querySelector(`[oncontextmenu*="${messageId}"]`);
                const contentDiv = messageContainer.querySelector('div:nth-child(2)');
                
                const editForm = document.createElement('textarea');
                editForm.className = 'edit-message';
                editForm.value = message.content || '';
                editForm.rows = 3;
                
                const buttonGroup = document.createElement('div');
                buttonGroup.className = 'mt-2';
                buttonGroup.innerHTML = `
                    <button class="btn btn-sm btn-success me-2" data-message-id="${messageId}" data-action="save">
                        <i class="bi bi-check"></i> Сохранить
                    </button>
                    <button class="btn btn-sm btn-secondary" data-message-id="${messageId}" data-action="cancel">
                        <i class="bi bi-x"></i> Отмена
                    </button>
                `;
                
                // Добавляем обработчики для кнопок
                buttonGroup.querySelectorAll('button').forEach(button => {
                    button.addEventListener('click', function() {
                        const action = this.getAttribute('data-action');
                        const msgId = parseInt(this.getAttribute('data-message-id'));
                        if (action === 'save') {
                            uiManager.saveMessageEdit(msgId);
                        } else if (action === 'cancel') {
                            uiManager.cancelMessageEdit(msgId);
                        }
                    });
                });
                
                contentDiv.innerHTML = '';
                contentDiv.appendChild(editForm);
                contentDiv.appendChild(buttonGroup);
                editForm.focus();
            }
        } catch (error) {
            console.error('Ошибка загрузки сообщения:', error);
        }
        this.hideContextMenu();
    }

    // Сохранение редактирования сообщения
    async saveMessageEdit(messageId) {
        try {
            const editForm = document.querySelector(`[oncontextmenu*="${messageId}"] .edit-message`);
            if (!editForm) {
                this.showError('Форма редактирования не найдена');
                return;
            }
            const newContent = editForm.value.trim();
            
            if (!newContent) {
                this.showError('Сообщение не может быть пустым');
                return;
            }
            
            const response = await fetch(`/api/messages/${messageId}`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ content: newContent })
            });
            
            if (response.ok) {
                this.showSuccess('Сообщение обновлено');
                if (window.chatManager && window.chatManager.loadMessages) {
                    await window.chatManager.loadMessages(window.chatManager.currentConversationId);
                }
            } else {
                this.showError('Ошибка обновления сообщения');
            }
        } catch (error) {
            console.error('Ошибка обновления:', error);
            this.showError('Ошибка соединения');
        }
        
        this.editingMessage = null;
    }

    // Отмена редактирования сообщения
    cancelMessageEdit(messageId) {
        this.editingMessage = null;
        if (window.chatManager && window.chatManager.loadMessages) {
            window.chatManager.loadMessages(window.chatManager.currentConversationId);
        }
    }

    // Удаление сообщения
    async deleteMessage(messageId) {
        if (!confirm('Вы уверены, что хотите удалить это сообщение?')) {
            return;
        }
        
        try {
            const response = await fetch(`/api/messages/${messageId}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                this.showSuccess('Сообщение удалено');
                if (window.chatManager && window.chatManager.loadMessages) {
                    await window.chatManager.loadMessages(window.chatManager.currentConversationId);
                }
            } else {
                this.showError('Ошибка удаления сообщения');
            }
        } catch (error) {
            console.error('Ошибка удаления:', error);
            this.showError('Ошибка соединения');
        }
        
        this.hideContextMenu();
    }

    // Показ модального окна создания чата
    showNewChatModal() {
        const modal = new bootstrap.Modal(document.getElementById('newChatModal'));
        modal.show();
    }

    // Показ модального окна заметки
    showNoteModal(noteId = null) {
        const modal = new bootstrap.Modal(document.getElementById('noteModal'));
        
        if (noteId) {
            if (window.noteManager && window.noteManager.loadNoteForEdit) {
                window.noteManager.loadNoteForEdit(noteId);
            }
        } else {
            const noteForm = document.getElementById('noteForm');
            const noteModalTitle = document.getElementById('noteModalTitle');
            const noteSaveBtn = document.getElementById('noteSaveBtn');
            
            if (noteForm) noteForm.reset();
            if (noteModalTitle) noteModalTitle.textContent = 'Новая заметка';
            if (noteSaveBtn) noteSaveBtn.textContent = 'Создать';
            // Обработчик для кнопки сохранения заметки будет добавлен в noteManager
        }
        
        modal.show();
    }

    // Показ загрузки файла
    showFileUpload() {
        const fileInput = document.getElementById('fileInput');
        if (fileInput) {
            fileInput.click();
        }
    }

    // Обработка выбора файла
    handleFileSelect(event) {
        const file = event.target.files[0];
        if (file && window.fileManager && window.fileManager.uploadFileToServer) {
            window.fileManager.uploadFileToServer(file);
        }
    }

    // Показ эмодзи пикера
    toggleEmojiPicker() {
        const picker = document.getElementById('emojiPicker');
        const button = document.getElementById('toggleEmojiPickerBtn');
        if (!picker || !button) return;
        
        if (picker.style.display === 'none' || picker.style.display === '') {
            // Позиционируем пикер относительно кнопки
            const buttonRect = button.getBoundingClientRect();
            picker.style.position = 'fixed';
            picker.style.bottom = (window.innerHeight - buttonRect.top) + 'px';
            picker.style.left = buttonRect.left + 'px';
            picker.style.zIndex = '9999';
            picker.style.display = 'block';
            console.log('🎭 Эмодзи пикер показан');
        } else {
            picker.style.display = 'none';
            console.log('🎭 Эмодзи пикер скрыт');
        }
    }

    // Вставка эмодзи
    insertEmoji(emoji) {
        const messageInput = document.getElementById('messageInput');
        if (!messageInput) return;
        
        const start = messageInput.selectionStart || 0;
        const end = messageInput.selectionEnd || 0;
        const text = messageInput.value || '';
        
        messageInput.value = text.substring(0, start) + emoji + text.substring(end);
        messageInput.focus();
        messageInput.setSelectionRange(start + emoji.length, start + emoji.length);
        
        const emojiPicker = document.getElementById('emojiPicker');
        if (emojiPicker) {
            emojiPicker.style.display = 'none';
        }
    }

    // Инициализация обработчиков событий
    initEventListeners() {
        // Отправка сообщения
        const messageForm = document.getElementById('messageForm');
        if (messageForm) {
            messageForm.addEventListener('submit', function(e) {
                e.preventDefault();
                if (window.chatManager && window.chatManager.sendMessage) {
                    window.chatManager.sendMessage();
                }
            });
        }
        
        // Обработчик для поиска участников (делегирование событий)
        document.addEventListener('input', function(e) {
            if (e.target.id === 'participantsSearch') {
                console.log('Поиск участников:', e.target.value); // Отладка
                if (window.searchManager && window.searchManager.searchUsers) {
                    window.searchManager.searchUsers(e.target.value);
                } else {
                    console.error('searchManager не инициализирован');
                }
            }
        });
        
        // Закрытие эмодзи пикера при клике вне его
        document.addEventListener('click', function(e) {
            const picker = document.getElementById('emojiPicker');
            if (!picker) return;
            
            const isClickInsidePicker = picker.contains(e.target);
            
            if (!isClickInsidePicker) {
                picker.style.display = 'none';
            }
        });

        // Отслеживание видимости страницы
        document.addEventListener('visibilitychange', function() {
            window.isPageVisible = !document.hidden;
        });
    }
}

// Создаем глобальный экземпляр
window.uiManager = new UIManager();
