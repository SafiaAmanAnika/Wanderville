// The Opus decoder for the Godot client.
//
// Godot has no Opus decoder of its own, so a client that wants compressed
// voice needs one. This is a GDExtension: a small class built against the
// official Godot bindings, wrapping the official libopus.
//
// The class is deliberately narrow. It decodes one Opus frame into PCM16
// samples and reports why it could not, and nothing else. The client checks
// that the decoder loaded before it asks the server for Opus, so a build
// without this extension keeps using raw PCM and loses nothing but the
// bandwidth saving.

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <gdextension_interface.h>

#include <opus.h>

namespace godot {

/// The sample rate and frame size the voice path uses: 48 kHz mono, 20 ms.
static const int SAMPLE_RATE = 48000;
static const int FRAME_SAMPLES = 960;

/// The longest frame libopus can produce, in samples. A 120 ms frame is the
/// limit of the format; the server sends 20 ms, but the decoder is given
/// room for anything it is handed.
static const int MAX_FRAME_SAMPLES = 5760;

class OpusDecoder : public RefCounted {
	GDCLASS(OpusDecoder, RefCounted)

	/// The libopus decoder. It is spelled with the global scope because
	/// libopus has a type of the same name.
	::OpusDecoder *codec = nullptr;
	String last_error;

protected:
	static void _bind_methods() {
		ClassDB::bind_method(D_METHOD("decode", "frame"), &OpusDecoder::decode);
		ClassDB::bind_method(D_METHOD("get_last_error"), &OpusDecoder::get_last_error);
	}

public:
	OpusDecoder() {
		int error = OPUS_OK;
		codec = opus_decoder_create(SAMPLE_RATE, 1, &error);
		if (error != OPUS_OK) {
			codec = nullptr;
			last_error = String("opus_decoder_create: ") + String(opus_strerror(error));
		}
	}

	~OpusDecoder() {
		if (codec != nullptr) {
			opus_decoder_destroy(codec);
			codec = nullptr;
		}
	}

	/// Decode one Opus frame into little-endian PCM16 mono samples.
	///
	/// Returns an empty array when the frame could not be decoded, with the
	/// reason in get_last_error(). A frame that arrives damaged is dropped
	/// by the client rather than played as noise.
	PackedByteArray decode(const PackedByteArray &frame) {
		PackedByteArray out;
		if (codec == nullptr) {
			if (last_error.is_empty()) {
				last_error = "The Opus decoder is not available";
			}
			return out;
		}
		if (frame.is_empty()) {
			return out;
		}
		opus_int16 samples[MAX_FRAME_SAMPLES];
		const int decoded = opus_decode(codec, frame.ptr(), (opus_int32)frame.size(), samples, MAX_FRAME_SAMPLES, 0);
		if (decoded < 0) {
			last_error = String(opus_strerror(decoded));
			return out;
		}
		out.resize(decoded * 2);
		for (int i = 0; i < decoded; i++) {
			out.encode_s16(i * 2, samples[i]);
		}
		return out;
	}

	String get_last_error() const {
		return last_error;
	}
};

static void initialize_wanderville_opus_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<OpusDecoder>();
}

static void uninitialize_wanderville_opus_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

} // namespace godot

extern "C" {

/// The entry point Godot calls to load this extension.
GDExtensionBool GDE_EXPORT wanderville_opus_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_object(p_get_proc_address, p_library, r_initialization);
	init_object.register_initializer(godot::initialize_wanderville_opus_module);
	init_object.register_terminator(godot::uninitialize_wanderville_opus_module);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
}
