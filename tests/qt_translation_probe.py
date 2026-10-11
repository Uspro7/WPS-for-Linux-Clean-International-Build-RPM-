"""Query the payload's real, namespaced Qt translator in a separate process."""
import ctypes as C
import json
from pathlib import Path
import sys


def probe(office, queries):
    qt = C.CDLL(str(Path(office) / 'libQt5CoreKso.so.5'))
    ptr = C.c_void_p
    def api(name, args, result=None):
        fn = getattr(qt, name)
        fn.argtypes, fn.restype = args, result
        return fn
    construct = api('_ZN6kso_qt11QTranslatorC1EPNS_7QObjectE', [ptr, ptr])
    string = api('_ZN6kso_qt7QStringC1EPKNS_5QCharEi', [ptr, ptr, C.c_int])
    load = api('_ZN6kso_qt11QTranslator4loadEPKhiRKNS_7QStringE',
               [ptr, ptr, C.c_int, ptr], C.c_bool)
    translate = api('_ZNK6kso_qt11QTranslator9translateEPKcS2_S2_i',
                    [ptr, ptr, C.c_char_p, C.c_char_p, C.c_char_p, C.c_int], ptr)
    utf16 = api('_ZNK6kso_qt7QString5utf16Ev', [ptr], ptr)
    empty = C.create_string_buffer(8)
    string(empty, None, 0)
    translators = {}
    results = []
    for component, context, source, comment in queries:
        if component not in translators:
            data = C.create_string_buffer((Path(office) / f'mui/zh_CN/{component}.qm').read_bytes())
            obj = C.create_string_buffer(1024)
            construct(obj, None)
            if not load(obj, data, len(data) - 1, empty):
                raise RuntimeError(f'Qt cannot load {component}.qm')
            # Keep the QM buffer alive: QTranslator::load does not copy it.
            translators[component] = (obj, data)
        result = C.create_string_buffer(8)
        translate(result, translators[component][0], context.encode(), source.encode(),
                  None if comment is None else comment.encode(), -1)
        backing = C.cast(result, C.POINTER(ptr))[0]
        length = C.c_int.from_address(backing + 4).value
        results.append(C.string_at(utf16(result), length * 2).decode('utf-16-le') if length else '')
    return results


if __name__ == '__main__':
    print(json.dumps(probe(sys.argv[1], json.load(sys.stdin)), ensure_ascii=False))
