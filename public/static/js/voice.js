// Модуль для работы с голосовыми сообщениями
class VoiceManager {
    constructor() {
        this.mediaRecorder = null;
        this.audioChunks = [];
        this.isRecording = false;
        this.recordingStartTime = null;
        this.recordingTimer = null;
        this.currentAudio = null;
    }

    // Переключение записи голоса
    async toggleVoiceRecording() {
        if (this.isRecording) {
            this.stopVoiceRecording();
        } else {
            await this.startVoiceRecording();
        }
    }

    // Начало записи голоса
    async startVoiceRecording() {
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            this.mediaRecorder = new MediaRecorder(stream);
            this.audioChunks = [];
            
            this.mediaRecorder.ondataavailable = (event) => {
                this.audioChunks.push(event.data);
            };
            
            this.mediaRecorder.onstop = () => {
                const audioBlob = new Blob(this.audioChunks, { type: 'audio/webm' });
                this.sendVoiceMessage(audioBlob);
                
                // Останавливаем все треки
                stream.getTracks().forEach(track => track.stop());
            };
            
            this.mediaRecorder.start();
            this.isRecording = true;
            this.recordingStartTime = Date.now();
            
            // Обновляем UI
            const voiceBtn = document.querySelector('[onclick*="toggleVoiceRecording"]');
            if (voiceBtn) {
                voiceBtn.classList.add('voice-recording');
                voiceBtn.innerHTML = '<i class="bi bi-stop-circle"></i>';
            }
            
            // Таймер записи
            this.recordingTimer = setInterval(() => {
                this.updateRecordingTime();
            }, 1000);
            
        } catch (error) {
            console.error('Ошибка записи:', error);
            uiManager.showError('Не удалось получить доступ к микрофону');
        }
    }

    // Остановка записи голоса
    stopVoiceRecording() {
        if (this.mediaRecorder && this.isRecording) {
            this.mediaRecorder.stop();
            this.isRecording = false;
            
            // Очищаем таймер
            if (this.recordingTimer) {
                clearInterval(this.recordingTimer);
                this.recordingTimer = null;
            }
            
            // Обновляем UI
            const voiceBtn = document.querySelector('[onclick*="toggleVoiceRecording"]');
            if (voiceBtn) {
                voiceBtn.classList.remove('voice-recording');
                voiceBtn.innerHTML = '<i class="bi bi-mic"></i>';
            }
        }
    }

    // Обновление времени записи
    updateRecordingTime() {
        if (this.isRecording && this.recordingStartTime) {
            const elapsed = Math.floor((Date.now() - this.recordingStartTime) / 1000);
            const timeStr = this.formatTime(elapsed);
            console.log(`Запись: ${timeStr}`);
        }
    }

    // Отправка голосового сообщения
    async sendVoiceMessage(audioBlob) {
        try {
            const formData = new FormData();
            formData.append('file', audioBlob, 'voice-message.webm');
            
            const response = await fetch('/api/files', {
                method: 'POST',
                body: formData
            });
            
            if (response.ok) {
                const result = await response.json();
                if (result.success) {
                    // Отправляем как сообщение
                    await this.sendVoiceAsMessage(result.id);
                } else {
                    uiManager.showError('Ошибка загрузки голосового сообщения');
                }
            } else {
                uiManager.showError('Ошибка загрузки файла');
            }
        } catch (error) {
            console.error('Ошибка отправки голосового сообщения:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Отправка голосового сообщения в чат
    async sendVoiceAsMessage(fileId) {
        try {
            const response = await fetch(`/api/conversations/${chatManager.currentConversationId}/messages`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ 
                    file_id: fileId,
                    message_type: 'voice'
                })
            });
            
            if (response.ok) {
                await chatManager.loadConversations();
                // Перезагружаем сообщения в текущем чате
                await chatManager.loadMessages(chatManager.currentConversationId);
            } else {
                uiManager.showError('Ошибка отправки сообщения');
            }
        } catch (error) {
            console.error('Ошибка отправки сообщения:', error);
            uiManager.showError('Ошибка соединения');
        }
    }

    // Воспроизведение голосового сообщения
    playVoiceMessage(storedName) {
        if (this.currentAudio) {
            this.currentAudio.pause();
            this.currentAudio = null;
        }
        
        this.currentAudio = new Audio(`/download/${storedName}`);
        
        this.currentAudio.onloadedmetadata = () => {
            // Обновляем длительность
            const duration = this.formatTime(this.currentAudio.duration);
            const durationElement = document.querySelector(`[onclick="voiceManager.playVoiceMessage('${storedName}')"]`).closest('.voice-message').querySelector('.voice-duration');
            if (durationElement) {
                durationElement.textContent = duration;
            }
        };
        
        this.currentAudio.onplay = () => {
            // Обновляем кнопку на паузу
            const button = document.querySelector(`[onclick="voiceManager.playVoiceMessage('${storedName}')"]`);
            if (button) {
                button.innerHTML = '<i class="bi bi-pause-circle"></i>';
            }
        };
        
        this.currentAudio.onpause = () => {
            // Обновляем кнопку на воспроизведение
            const button = document.querySelector(`[onclick="voiceManager.playVoiceMessage('${storedName}')"]`);
            if (button) {
                button.innerHTML = '<i class="bi bi-play-circle"></i>';
            }
        };
        
        this.currentAudio.onended = () => {
            // Обновляем кнопку на воспроизведение
            const button = document.querySelector(`[onclick="voiceManager.playVoiceMessage('${storedName}')"]`);
            if (button) {
                button.innerHTML = '<i class="bi bi-play-circle"></i>';
            }
            this.currentAudio = null;
        };
        
        this.currentAudio.onerror = (error) => {
            console.error('Ошибка воспроизведения:', error);
            uiManager.showError('Ошибка воспроизведения аудио');
        };
        
        if (this.currentAudio.paused) {
            this.currentAudio.play();
        } else {
            this.currentAudio.pause();
        }
    }

    // Форматирование времени
    formatTime(seconds) {
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }
}

// Создаем глобальный экземпляр
window.voiceManager = new VoiceManager();
