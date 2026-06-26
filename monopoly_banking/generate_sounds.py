import os
import wave
import math
import struct

def generate_tone(filename, duration, freqs, decay=True, envelope_type='exp'):
    sample_rate = 44100

    os.makedirs(os.path.dirname(filename), exist_ok=True)

    with wave.open(filename, 'w') as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)

        n_samples = int(sample_rate * duration)

        for i in range(n_samples):
            t = float(i) / sample_rate
            value = 0
            for f in freqs:
                value += math.sin(2.0 * math.pi * f * t)
            value /= len(freqs)

            # Envelope
            if decay:
                if envelope_type == 'exp':
                    env = math.exp(-5.0 * t / duration)
                else:
                    env = 1.0 - (t / duration)
            else:
                env = 1.0

            sample = int(value * env * 32767.0 * 0.4)
            wav_file.writeframes(struct.pack('<h', sample))

# Generar un click corto para botones
generate_tone('assets/sounds/click.wav', 0.1, [600, 800], decay=True, envelope_type='exp')

# Generar sonido de caja registradora o monedas (Cash)
generate_tone('assets/sounds/cash.wav', 0.5, [1200, 1500, 2000], decay=True, envelope_type='exp')

# Generar un arpegio simple de fondo (Theme musical)
# Haremos una melodía simple combinando tonos
sample_rate = 44100
duration = 16.0
filename = 'assets/sounds/theme.wav'
os.makedirs(os.path.dirname(filename), exist_ok=True)
with wave.open(filename, 'w') as wav_file:
    wav_file.setnchannels(1)
    wav_file.setsampwidth(2)
    wav_file.setframerate(sample_rate)

    notes = [261.63, 329.63, 392.00, 523.25] # C, E, G, C
    note_duration = 0.25
    total_samples = int(sample_rate * duration)

    for i in range(total_samples):
        t = float(i) / sample_rate
        note_idx = int((t % 1.0) / note_duration) % 4
        f = notes[note_idx]

        value = math.sin(2.0 * math.pi * f * t)

        # Envelope por nota
        t_note = t % note_duration
        env = math.exp(-3.0 * t_note / note_duration)

        # Volumen bajo para la musica de fondo
        sample = int(value * env * 32767.0 * 0.1)
        wav_file.writeframes(struct.pack('<h', sample))

print("Archivos de audio generados exitosamente.")
