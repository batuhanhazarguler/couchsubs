# SPDX-License-Identifier: AGPL-3.0-only
"""Strong English swearing must be recognised so correct hard fixes are applied, not vetoed.

Küfür kuralı: çeviride küfür asla sansürlenmez ve yumuşatılmaz. Eksik STRONG_EN sözcükleri, yumuşak çeviriyi
sert karşılığıyla düzelten doğru önerileri "added-profanity" diye geri çeviriyordu.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run_review(en, old, proposed):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        for name in ("review.py", "common.py", "atomic_json.py"):
            shutil.copy2(HERE / name, root / name)
        (root / "translate_rules.py").write_text("GLOSSARY = {'ds': ''}\nRULES = ''\n", encoding="utf-8")
        (root / "llm.py").write_text(
            "def call(*args, **kwargs):\n"
            + "    return {'fixes': [{'id': '0.0', 'tr': " + repr(proposed) + ", 'why': 'profanity'}]}\n"
            + "def spent(): return 0.0\n", encoding="utf-8")
        source = root / "source.json"
        source.write_text(json.dumps([{"speaker": "", "text": en, "sents": [en], "tr": [old]}]), encoding="utf-8")
        output = root / "reviewed.json"
        result = subprocess.run([sys.executable, "-B", str(root / "review.py"), "ds", str(source), str(output)],
                                cwd=root, capture_output=True, text=True, encoding="utf-8", errors="replace")
        if result.returncode != 0:
            raise AssertionError(result.stdout + result.stderr)
        lines = json.loads(output.read_text(encoding="utf-8"))
        log = json.loads((root / "reviewed.json.log.json").read_text(encoding="utf-8"))
        return lines[0]["tr"][0], log, result.stdout


class ReviewStrongProfanityTests(unittest.TestCase):
    # (English, softened old translation, correct hard fix)
    CASES = [
        ("Move your ass!", "Hadi acele et!", "Kaldır kıçını!"),
        ("You dumbass.", "Seni salak.", "Seni göt herif."),
        ("Shut up, you whore.", "Kapa çeneni, kadın.", "Kapa çeneni, orospu."),
        ("She's a slut.", "O hafif bir kadın.", "O bir sürtük."),
        ("What a prick.", "Ne kaba adam.", "Ne yarak kafalı herif."),
        ("Don't be a pussy.", "Korkak olma.", "Amcık olma."),
        ("Where you at, nigga?", "Neredesin, kanka?", "Neredesin lan piç?"),
        ("Those niggas owe me.", "O herifler bana borçlu.", "O piçler bana borçlu."),
    ]

    def test_hard_fix_for_missing_strong_words_is_applied(self):
        for en, old, fix in self.CASES:
            with self.subTest(en=en):
                translated, log, _ = run_review(en, old, fix)
                self.assertEqual(log["vetoed"], [])
                self.assertEqual(translated, fix)

    def test_soft_translation_of_strong_word_is_flagged_softened(self):
        for en, old, _ in self.CASES:
            with self.subTest(en=en):
                _, _, stdout = run_review(en, old, old + " ")
                self.assertIn("'softened': 1", stdout)

    def test_euphemism_replacing_hard_swear_is_vetoed(self):
        # "asshole" -> "pislik" yumuşatmadır: sert çeviriyi pislik'e çeviren öneri geri çevrilir.
        translated, log, _ = run_review("You asshole!", "Seni göt herif!", "Seni pislik!")
        self.assertEqual(translated, "Seni göt herif!")
        self.assertTrue(log["vetoed"][0]["veto"].startswith("new-problem:"))
        translated, log, _ = run_review("Don't be a pussy.", "Amcık olma.", "Korkak olma.")
        self.assertEqual(translated, "Amcık olma.")
        self.assertIn("softened", log["vetoed"][0]["veto"])

    def test_ordinary_words_are_not_strong(self):
        for en in ("The assassin will pass the class.", "The pricking cold.", "Grab the glass, please."):
            with self.subTest(en=en):
                translated, log, _ = run_review(en, "Bu eski bir numara.", "Siktir git, bu eski bir numara.")
                self.assertEqual(translated, "Bu eski bir numara.")
                self.assertEqual(log["vetoed"][0]["veto"], "added-profanity")


if __name__ == "__main__":
    unittest.main()
