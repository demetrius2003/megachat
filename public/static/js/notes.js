// Модуль для работы с заметками
class NoteManager {
    constructor() {
        this.notes = [];
    }

    // Загрузка заметок
    async loadNotes() {
        try {
            const response = await fetch('/api/notes');
            if (response.ok) {
                this.notes = await response.json();
                return this.notes;
            }
        } catch (error) {
            console.error('Ошибка загрузки заметок:', error);
        }
        return [];
    }

    // Загрузка заметки для редактирования
    async loadNoteForEdit(noteId) {
        try {
            const response = await fetch('/api/notes');
            if (response.ok) {
                const notes = await response.json();
                const note = notes.find(n => n.id === noteId);
                if (note) {
                    document.getElementById('noteTitle').value = note.title;
                    document.getElementById('noteContent').value = note.content;
                    document.getElementById('noteColor').value = note.color;
                    document.getElementById('noteModalTitle').textContent = 'Редактировать заметку';
                    document.getElementById('noteSaveBtn').textContent = 'Сохранить';
                    document.getElementById('noteSaveBtn').onclick = () => this.updateNote(noteId);
                }
            }
        } catch (error) {
            console.error('Ошибка загрузки заметки:', error);
        }
    }

    // Создание заметки
    async createNote() {
        console.log('📝 Создание заметки...');
        const title = document.getElementById('noteTitle').value.trim();
        const content = document.getElementById('noteContent').value.trim();
        const color = document.getElementById('noteColor').value;
        
        console.log('📝 Данные заметки:', { title, content, color });
        
        if (!title) {
            console.log('📝 Ошибка: заголовок пустой');
            uiManager.showError('Введите заголовок заметки');
            return;
        }
        
        try {
            console.log('📝 Отправляем запрос к API...');
            const response = await fetch('/api/notes', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ title, content, color })
            });
            
            console.log('📝 Ответ API:', response.status);
            
            if (response.ok) {
                const result = await response.json();
                console.log('📝 Результат API:', result);
                if (result.success) {
                    console.log('📝 Заметка успешно создана!');
                    uiManager.showSuccess('Заметка создана');
                    bootstrap.Modal.getInstance(document.getElementById('noteModal')).hide();
                    document.getElementById('noteForm').reset();
                    await chatManager.loadConversations();
                } else {
                    console.log('📝 Ошибка: API вернул success: false');
                    uiManager.showError('Ошибка создания заметки');
                }
            } else {
                console.log('📝 Ошибка: HTTP статус', response.status);
                uiManager.showError('Ошибка создания заметки');
            }
        } catch (error) {
            console.error('📝 Ошибка создания заметки:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Обновление заметки
    async updateNote(noteId) {
        const title = document.getElementById('noteTitle').value.trim();
        const content = document.getElementById('noteContent').value.trim();
        const color = document.getElementById('noteColor').value;
        
        if (!title) {
            uiManager.showError('Введите заголовок заметки');
            return;
        }
        
        try {
            const response = await fetch(`/api/notes/${noteId}`, {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ title, content, color })
            });
            
            if (response.ok) {
                uiManager.showSuccess('Заметка обновлена');
                bootstrap.Modal.getInstance(document.getElementById('noteModal')).hide();
                await chatManager.loadConversations();
            } else {
                uiManager.showError('Ошибка обновления заметки');
            }
        } catch (error) {
            console.error('Ошибка обновления заметки:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Удаление заметки
    async deleteNote(noteId) {
        if (!confirm('Вы уверены, что хотите удалить эту заметку?')) {
            return;
        }
        
        try {
            const response = await fetch(`/api/notes/${noteId}`, {
                method: 'DELETE'
            });
            
            if (response.ok) {
                uiManager.showSuccess('Заметка удалена');
                await chatManager.loadConversations();
            } else {
                uiManager.showError('Ошибка удаления заметки');
            }
        } catch (error) {
            console.error('Ошибка удаления заметки:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Поделиться заметкой
    async shareNote(noteId) {
        if (chatManager.currentConversationId) {
            try {
                const response = await fetch(`/api/conversations/${chatManager.currentConversationId}/messages`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({ 
                        note_id: noteId,
                        message_type: 'note'
                    })
                });
                
                if (response.ok) {
                    uiManager.showSuccess('Заметка отправлена в чат');
                    await chatManager.loadConversations();
                } else {
                    uiManager.showError('Ошибка отправки заметки');
                }
            } catch (error) {
                console.error('Ошибка отправки заметки:', error);
                uiManager.showError('Ошибка соединения');
            }
        } else {
            uiManager.showError('Выберите чат для отправки');
        }
    }
}

// Создаем глобальный экземпляр
window.noteManager = new NoteManager();
