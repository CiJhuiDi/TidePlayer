/*
 * tide_audio.c 鈥?Tide Player 鐨勯煶棰戝悗绔紙Windows DLL锛? *
 * 鐢?minimp3 瑙ｇ爜 mp3 + waveOut 杈撳嚭 PCM銆備笉鐢?MCI锛屽洜涓烘殫娼繘绋嬮噷
 * MCI 鐨?mpegvideo 椹卞姩鍒濆鍖栦細澶辫触锛圡CIERR 267銆屽垵濮嬪寲 MCI 鏃跺彂鐢熼棶棰樸€嶏級锛? * 鑰?waveOut 鍦ㄨ繖涓繘绋嬮噷鏄ソ鐨勶紙RimWorldAlerts 灏遍潬瀹冩斁鎻愮ず闊筹級銆? *
 * 娴佺▼锛歮od 鍏堢敤 curl 鎶婃瓕涓嬭浇鍒?cache锛屽啀璋?TaPlayFile(path)銆? * 杩欓噷鍚屾鎵撳紑銆佸紓姝ユ挱鏀撅細鎾斁绾跨▼鎸?buffer 瑙ｇ爜/鍐欒澶囷紝
 * Lua 渚у彧璇?TaState / TaPosition / TaLength銆? *
 * 缂栬瘧锛圡inGW64锛屾簮鐩綍閲屽甫 minimp3.h / minimp3_ex.h锛夛細
 *   gcc -shared -O2 -static-libgcc -o tide_audio.dll tide_audio.c -lwinmm -lm
 */

#define MINIMP3_IMPLEMENTATION
#include "minimp3_ex.h"

#include <windows.h>
#include <mmsystem.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <math.h>

#define TA_BUFFER_COUNT 16
#define TA_FRAME_SAMPLES 1024
#define TA_FFT_SIZE 512
#define TA_BAND_COUNT 24

static HWAVEOUT g_waveout = NULL;
static WAVEHDR g_headers[TA_BUFFER_COUNT];
static short *g_buffers[TA_BUFFER_COUNT];
static int g_buffer_count = 0;
static HANDLE g_thread = NULL;
static mp3dec_ex_t g_decoder;
static int g_decoder_open = 0;
static int g_channels = 2;
static int g_sample_rate = 44100;
static volatile LONG g_stop = 0;
static volatile LONG g_state = 0; /* 0=idle 1=playing 2=paused 3=stopped */
static volatile LONG g_volume = 700; /* 0..1000 */
static volatile LONG g_finished = 0;
static volatile LONG g_level = 0;
static volatile LONG g_spectrum[TA_BAND_COUNT];
static float g_fft_re[TA_FFT_SIZE];
static float g_fft_im[TA_FFT_SIZE];
static float g_hann[TA_FFT_SIZE];
static int g_fft_ready = 0;
static wchar_t g_last_error[512];
static CRITICAL_SECTION g_lock;
static int g_lock_ready = 0;

static void set_error(const wchar_t *message)
{
	wcsncpy(g_last_error, message, 511);
	g_last_error[511] = 0;
}

static void set_errorf(const wchar_t *format, long value)
{
	swprintf(g_last_error, 512, format, value);
}

static void release_playback(void)
{
	if (g_waveout) {
		waveOutReset(g_waveout);
	}

	if (g_thread) {
		g_stop = 1;
		WaitForSingleObject(g_thread, 3000);
		CloseHandle(g_thread);
		g_thread = NULL;
	}

	if (g_waveout) {
		for (int i = 0; i < g_buffer_count; i++) {
			waveOutUnprepareHeader(g_waveout, &g_headers[i], sizeof(WAVEHDR));
		}

		waveOutClose(g_waveout);
		g_waveout = NULL;
	}

	for (int i = 0; i < g_buffer_count; i++) {
		if (g_buffers[i]) {
			free(g_buffers[i]);
			g_buffers[i] = NULL;
		}
	}

	g_buffer_count = 0;

	if (g_decoder_open) {
		mp3dec_ex_close(&g_decoder);
		g_decoder_open = 0;
	}

	memset(g_headers, 0, sizeof(g_headers));
}

/* ---------------- 频谱 ---------------- */

static void fft_init(void)
{
	if (g_fft_ready) {
		return;
	}

	for (int i = 0; i < TA_FFT_SIZE; i++) {
		g_hann[i] = 0.5f - 0.5f * cosf(6.28318530718f * (float)i / (float)(TA_FFT_SIZE - 1));
	}

	g_fft_ready = 1;
}

static void fft_run(void)
{
	int n = TA_FFT_SIZE;

	for (int i = 1, j = 0; i < n; i++) {
		int bit = n >> 1;

		for (; j & bit; bit >>= 1) {
			j ^= bit;
		}

		j ^= bit;

		if (i < j) {
			float tr = g_fft_re[i];
			float ti = g_fft_im[i];

			g_fft_re[i] = g_fft_re[j];
			g_fft_im[i] = g_fft_im[j];
			g_fft_re[j] = tr;
			g_fft_im[j] = ti;
		}
	}

	for (int len = 2; len <= n; len <<= 1) {
		float ang = -6.28318530718f / (float)len;
		float wlen_re = cosf(ang);
		float wlen_im = sinf(ang);

		for (int i = 0; i < n; i += len) {
			float wr = 1.0f;
			float wi = 0.0f;

			for (int j = 0; j < len / 2; j++) {
				int a = i + j;
				int b = a + len / 2;
				float vr = g_fft_re[b] * wr - g_fft_im[b] * wi;
				float vi = g_fft_re[b] * wi + g_fft_im[b] * wr;
				float ur = g_fft_re[a];
				float ui = g_fft_im[a];

				g_fft_re[a] = ur + vr;
				g_fft_im[a] = ui + vi;
				g_fft_re[b] = ur - vr;
				g_fft_im[b] = ui - vi;

				float nwr = wr * wlen_re - wi * wlen_im;

				wi = wr * wlen_im + wi * wlen_re;
				wr = nwr;
			}
		}
	}
}

/* 对一块原始 PCM 做 512 点 FFT，按对数频率切成 24 个频段 */
static void compute_spectrum(const short *pcm, int channels)
{
	int n = TA_FFT_SIZE;
	int bins = n / 2;
	float min_f = 40.0f;
	float max_f = 16000.0f;
	float rate = (float)(g_sample_rate > 0 ? g_sample_rate : 44100);

	fft_init();

	for (int i = 0; i < n; i++) {
		float v = (float)pcm[i * channels] / 32768.0f;

		g_fft_re[i] = v * g_hann[i];
		g_fft_im[i] = 0.0f;
	}

	fft_run();

	float mags[TA_BAND_COUNT];
	float max_mag = 0.0f;

	for (int band = 0; band < TA_BAND_COUNT; band++) {
		float f0 = min_f * powf(max_f / min_f, (float)band / (float)TA_BAND_COUNT);
		float f1 = min_f * powf(max_f / min_f, (float)(band + 1) / (float)TA_BAND_COUNT);
		int bin0 = (int)(f0 * (float)n / rate);
		int bin1 = (int)(f1 * (float)n / rate);
		float mag = 0.0f;

		if (bin0 < 1) {
			bin0 = 1;
		}

		if (bin1 <= bin0) {
			bin1 = bin0 + 1;
		}

		if (bin1 > bins) {
			bin1 = bins;
		}

		for (int k = bin0; k < bin1; k++) {
			float value = sqrtf(g_fft_re[k] * g_fft_re[k] + g_fft_im[k] * g_fft_im[k]);

			if (value > mag) {
				mag = value;
			}
		}

		/* pink-noise 趋势补偿：低频压一点、高频抬一点 */
		{
			float f_center = sqrtf(f0 * f1);
			mag *= powf(f_center / 500.0f, 0.5f);
		}

		mags[band] = mag;

		if (mag > max_mag) {
			max_mag = mag;
		}
	}

	{
		float abs_db = 20.0f * log10f(max_mag + 1e-9f);
		float abs_norm = (abs_db + 80.0f) / 80.0f;

		if (abs_norm < 0.0f) {
			abs_norm = 0.0f;
		}

		if (abs_norm > 1.0f) {
			abs_norm = 1.0f;
		}

		for (int i = 0; i < TA_BAND_COUNT; i++) {
			float rel = mags[i] / (max_mag + 1e-9f);
			float norm = powf(rel, 0.65f) * (0.25f + 0.75f * abs_norm);
			LONG target = (LONG)(norm * 1000.0f);

			g_spectrum[i] = (g_spectrum[i] + target * 3) / 4;
		}
	}
}

static DWORD WINAPI playback_thread(LPVOID parameter)
{
	int next_index = 0;
	int active = 0;

	(void)parameter;

	for (;;) {
		size_t read_count;
		int slot = -1;

		if (g_stop) {
			break;
		}

		for (int i = 0; i < g_buffer_count; i++) {
			int index = (next_index + i) % g_buffer_count;

			if (g_headers[index].dwFlags & WHDR_DONE || g_headers[index].dwBufferLength == 0) {
				slot = index;
				break;
			}
		}

		if (slot < 0) {
			Sleep(5);
			continue;
		}

		next_index = (slot + 1) % g_buffer_count;

		read_count = mp3dec_ex_read(&g_decoder, g_buffers[slot], TA_FRAME_SAMPLES * g_channels);

		if (read_count == 0) {
			break;
		}

		{
			/* 电平：先量原始 PCM 的峰值，不随播放器音量变化——
			   示波器看的是音乐本身的动静，音量关小不该把波形压平 */
			long peak = 0;
			LONG target;

			for (size_t i = 0; i < read_count; i++) {
				long sample = g_buffers[slot][i];

				if (sample < 0) {
					sample = -sample;
				}

				if (sample > peak) {
					peak = sample;
				}
			}

			target = (LONG)((peak * 1000) / 32768);

			if (target > 1000) {
				target = 1000;
			}

			g_level = (g_level * 2 + target) / 3;
		}

		compute_spectrum(g_buffers[slot], g_channels);

		{
			long volume = g_volume;

			if (volume != 1000) {
				for (size_t i = 0; i < read_count; i++) {
					g_buffers[slot][i] = (short)(((long)g_buffers[slot][i] * volume) / 1000);
				}
			}
		}

		g_headers[slot].dwBufferLength = (DWORD)(read_count * sizeof(short));
		g_headers[slot].dwFlags &= ~WHDR_DONE;

		if (waveOutWrite(g_waveout, &g_headers[slot], sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
			set_error(L"waveOutWrite failed");

			break;
		}

		active = 1;
	}

	/* 绛夋渶鍚庡嚑涓?buffer 鏀惧畬锛涙殏鍋滄椂涓嶈绛夛紝鍚﹀垯 stop 浼氭嫋浣?*/
	if (active) {
		for (int i = 0; i < 200; i++) {
			int pending = 0;

			if (g_stop) {
				break;
			}

			for (int j = 0; j < g_buffer_count; j++) {
				if (g_headers[j].dwBufferLength > 0 && !(g_headers[j].dwFlags & WHDR_DONE)) {
					pending = 1;
				}
			}

			if (!pending) {
				break;
			}

			Sleep(10);
		}
	}

	if (!g_stop) {
		g_state = 3;
	}

	return 0;
}

static int start_playback(void)
{
	WAVEFORMATEX format;

	memset(&format, 0, sizeof(format));

	format.wFormatTag = WAVE_FORMAT_PCM;
	format.nChannels = (WORD)g_channels;
	format.nSamplesPerSec = (DWORD)g_sample_rate;
	format.wBitsPerSample = 16;
	format.nBlockAlign = (WORD)(format.nChannels * format.wBitsPerSample / 8);
	format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;

	if (waveOutOpen(&g_waveout, WAVE_MAPPER, &format, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR) {
		set_error(L"waveOutOpen failed");

		return -3;
	}

	g_buffer_count = TA_BUFFER_COUNT;

	for (int i = 0; i < g_buffer_count; i++) {
		g_buffers[i] = (short *)malloc(sizeof(short) * TA_FRAME_SAMPLES * g_channels);

		if (!g_buffers[i]) {
			release_playback();

			return -4;
		}

		memset(&g_headers[i], 0, sizeof(WAVEHDR));
		g_headers[i].lpData = (LPSTR)g_buffers[i];
		g_headers[i].dwBufferLength = 0;

		if (waveOutPrepareHeader(g_waveout, &g_headers[i], sizeof(WAVEHDR)) != MMSYSERR_NOERROR) {
			release_playback();

			return -5;
		}

		g_headers[i].dwFlags |= WHDR_DONE;
	}

	g_stop = 0;
	g_state = 1;
	g_finished = 0;

	g_thread = CreateThread(NULL, 0, playback_thread, NULL, 0, NULL);

	if (!g_thread) {
		release_playback();

		return -6;
	}

	return 0;
}

/* ------------------------------------------------------------------ */
/* 瀵煎嚭鎺ュ彛                                                            */
/* ------------------------------------------------------------------ */

__declspec(dllexport) int TaInit(void)
{
	if (!g_lock_ready) {
		InitializeCriticalSection(&g_lock);
		g_lock_ready = 1;
	}

	return 0;
}

__declspec(dllexport) int TaPlayFile(const wchar_t *path, int volume)
{
	int result;

	if (!path) {
		return -1;
	}

	TaInit();

	if (volume < 0) {
		volume = 0;
	}
	if (volume > 1000) {
		volume = 1000;
	}

	g_volume = volume;

	EnterCriticalSection(&g_lock);
	release_playback();

	memset(&g_decoder, 0, sizeof(g_decoder));

	result = mp3dec_ex_open_w(&g_decoder, path, MP3D_SEEK_TO_SAMPLE);

	if (result != 0) {
		set_error(L"could not decode mp3 file");
		LeaveCriticalSection(&g_lock);

		return -2;
	}

	g_decoder_open = 1;
	g_channels = g_decoder.info.channels > 0 ? g_decoder.info.channels : 2;
	g_sample_rate = g_decoder.info.hz > 0 ? g_decoder.info.hz : 44100;

	result = start_playback();
	LeaveCriticalSection(&g_lock);

	return result;
}

__declspec(dllexport) int TaPause(void)
{
	if (!g_waveout || g_state != 1) {
		return -1;
	}

	if (waveOutPause(g_waveout) != MMSYSERR_NOERROR) {
		return -2;
	}

	g_level = 0;

	for (int i = 0; i < TA_BAND_COUNT; i++) {
		g_spectrum[i] = 0;
	}

	g_state = 2;

	return 0;
}

__declspec(dllexport) int TaResume(void)
{
	if (!g_waveout || g_state != 2) {
		return -1;
	}

	if (waveOutRestart(g_waveout) != MMSYSERR_NOERROR) {
		return -2;
	}

	g_state = 1;

	return 0;
}

__declspec(dllexport) int TaStop(void)
{
	EnterCriticalSection(&g_lock);
	release_playback();
	g_level = 0;

	for (int i = 0; i < TA_BAND_COUNT; i++) {
		g_spectrum[i] = 0;
	}

	g_state = 0;
	LeaveCriticalSection(&g_lock);

	return 0;
}

__declspec(dllexport) int TaSetVolume(int volume)
{
	if (volume < 0) {
		volume = 0;
	}
	if (volume > 1000) {
		volume = 1000;
	}

	g_volume = volume;

	return 0;
}

/* 0=idle 1=playing 2=paused 3=stopped */
__declspec(dllexport) int TaState(void)
{
	return (int)g_state;
}

/* 当前 PCM 峰值电平，0..1000 */
__declspec(dllexport) int TaLevel(void)
{
	return (int)g_level;
}

/* 24 个频段的能量，0..1000；count 最多 24 */
__declspec(dllexport) void TaGetSpectrum(int *out, int count)
{
	if (!out) {
		return;
	}

	if (count > TA_BAND_COUNT) {
		count = TA_BAND_COUNT;
	}

	for (int i = 0; i < count; i++) {
		out[i] = (int)g_spectrum[i];
	}
}

__declspec(dllexport) int TaPosition(void)
{
	MMTIME time;
	UINT64 samples_per_second;

	if (!g_waveout || g_state == 0) {
		return 0;
	}

	memset(&time, 0, sizeof(time));
	time.wType = TIME_SAMPLES;

	if (waveOutGetPosition(g_waveout, &time, sizeof(time)) != MMSYSERR_NOERROR) {
		return 0;
	}

	if (time.wType != TIME_SAMPLES) {
		return 0;
	}

	/* TIME_SAMPLES 给的是每声道样本数，分母只算采样率，不能乘声道数 */
	samples_per_second = (UINT64)g_sample_rate;

	if (samples_per_second == 0) {
		return 0;
	}

	return (int)((UINT64)time.u.sample * 1000 / samples_per_second);
}

__declspec(dllexport) int TaLength(void)
{
	UINT64 samples;
	UINT64 samples_per_second;

	if (!g_decoder_open || g_decoder.samples == 0) {
		return 0;
	}

	samples = g_decoder.samples;
	samples_per_second = (UINT64)g_sample_rate * (UINT64)g_channels;

	if (samples_per_second == 0) {
		return 0;
	}

	return (int)(samples * 1000 / samples_per_second);
}

__declspec(dllexport) const wchar_t *TaLastError(void)
{
	return g_last_error;
}

__declspec(dllexport) void TaShutdown(void)
{
	TaInit();

	EnterCriticalSection(&g_lock);
	release_playback();
	g_state = 0;
	LeaveCriticalSection(&g_lock);
}
