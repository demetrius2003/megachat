// Модуль для работы с файлами
class FileManager {
    constructor() {
        this.files = [];
    }

    // Загрузка файлов
    async loadFiles() {
        try {
            const response = await fetch('/api/files');
            if (response.ok) {
                this.files = await response.json();
                return this.files;
            }
        } catch (error) {
            console.error('Ошибка загрузки файлов:', error);
        }
        return [];
    }

    // Загрузка файла на сервер
    async uploadFileToServer(file) {
        const formData = new FormData();
        formData.append('file', file);
        
        // Показываем превью для изображений
        if (file.type.startsWith('image/')) {
            this.showImagePreview(file);
        }
        
        try {
            const response = await fetch('/api/files', {
                method: 'POST',
                body: formData
            });
            
            if (response.ok) {
                const result = await response.json();
                if (result.success) {
                    uiManager.showSuccess('Файл загружен');
                    
                    // Если это изображение, отправляем как сообщение
                    if (file.type.startsWith('image/')) {
                        await this.sendFileAsMessage(result.id, 'image');
                    } else {
                        await this.sendFileAsMessage(result.id, 'file');
                    }
                } else {
                    uiManager.showError('Ошибка загрузки файла');
                }
            } else {
                uiManager.showError('Ошибка загрузки файла');
            }
        } catch (error) {
            console.error('Ошибка загрузки файла:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Отправка файла как сообщение
    async sendFileAsMessage(fileId, messageType) {
        try {
            const response = await fetch(`/api/conversations/${chatManager.currentConversationId}/messages`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ 
                    file_id: fileId,
                    message_type: messageType
                })
            });
            
            if (response.ok) {
                await chatManager.loadConversations();
                // Перезагружаем сообщения в текущем чате
                await chatManager.loadMessages(chatManager.currentConversationId);
            } else {
                uiManager.showError('Ошибка отправки файла');
            }
        } catch (error) {
            console.error('Ошибка отправки файла:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Показ превью изображения
    showImagePreview(file) {
        const reader = new FileReader();
        reader.onload = (e) => {
            const preview = document.createElement('div');
            preview.className = 'image-preview mb-2';
            preview.innerHTML = `
                <img src="${e.target.result}" class="img-fluid rounded" style="max-width: 200px; max-height: 150px;">
                <div class="mt-1">
                    <small class="text-muted">${file.name} (${this.formatFileSize(file.size)})</small>
                </div>
            `;
            
            const messageInput = document.getElementById('messageInput');
            messageInput.parentNode.insertBefore(preview, messageInput);
            
            // Удаляем превью через 5 секунд
            setTimeout(() => {
                preview.remove();
            }, 5000);
        };
        reader.readAsDataURL(file);
    }

    // Форматирование размера файла
    formatFileSize(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }

    // Скачивание файла
    downloadFile(storedName) {
        window.open(`/download/${storedName}`, '_blank');
    }

    // Удаление файла
    async deleteFile(fileId) {
        if (!confirm('Вы уверены, что хотите удалить этот файл?')) {
            return;
        }
        
        try {
            const response = await fetch(`/api/files/${fileId}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                uiManager.showSuccess('Файл удален');
                await chatManager.loadConversations();
            } else {
                uiManager.showError('Ошибка удаления файла');
            }
        } catch (error) {
            console.error('Ошибка удаления файла:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Поделиться файлом
    async shareFile(fileId) {
        if (chatManager.currentConversationId) {
            try {
                const response = await fetch(`/api/conversations/${chatManager.currentConversationId}/messages`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ 
                        file_id: fileId,
                        message_type: 'file'
                    })
                });
                
                if (response.ok) {
                    uiManager.showSuccess('Файл отправлен в чат');
                    await chatManager.loadConversations();
                } else {
                    uiManager.showError('Ошибка отправки файла');
                }
            } catch (error) {
                console.error('Ошибка отправки файла:', error);
                uiManager.showError('Ошибка соединения');
            }
        } else {
            uiManager.showError('Выберите чат для отправки');
        }
    }
}

// Создаем глобальный экземпляр
window.fileManager = new FileManager();
