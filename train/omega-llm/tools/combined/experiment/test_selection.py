"""Controls independent of the 80 final tasks. Run with python3 -m unittest test_selection."""
import unittest
from unittest.mock import patch

from selection import choose, disagreement


class MockEngine:
    def predict(self, body, xs):
        return [(int(x[0] == 9 and body == b"long"),) for x in xs]


class Controls(unittest.TestCase):
    fixed = [(i,) for i in range(8)]
    pool = [(8,), (9,), *fixed]

    def check_run(self, generate, oracle=lambda x: (0,), adaptive=True):
        seen=[]
        def query(x):
            self.assertNotIn(x,seen)
            seen.append(x)
            return oracle(x)
        with patch("selection.candidates",side_effect=generate):
            result=choose(MockEngine(),self.fixed,self.pool,query,adaptive)
        self.assertEqual(len(seen),8)
        return result,seen

    def test_disagreement(self):
        self.assertEqual(disagreement([0,0,1,1]),4)
        self.assertEqual(disagreement([None,0,0,0]),3)
        result, xs = self.check_run(lambda *_: [("sketch",b"s"),("synth",b"long")],
                                    lambda x:(int(x==(9,)),))
        self.assertEqual(xs[4],(9,))
        self.assertEqual(result[:2],(b"long","synth"))
        self.assertEqual(xs[5:],self.fixed[4:7])

    def test_tie_order_and_shortest(self):
        result,xs=self.check_run(lambda *_: [("first",b"aa"),("second",b"bb"),("short",b"s")])
        self.assertEqual(xs,self.fixed)
        self.assertEqual(result[:2],(b"s","short"))
        result,_=self.check_run(lambda *_:[("first",b"aa"),("second",b"bb")],adaptive=False)
        self.assertEqual(result[:2],(b"aa","first"))

    def test_regeneration_and_abstention(self):
        calls=[]
        def after_empty(engine, rows):
            calls.append(len(rows))
            return [] if len(rows)<6 else [("late",b"s")]
        result,_=self.check_run(after_empty)
        self.assertEqual(calls,[4,5,6])
        self.assertEqual(result[:2],(b"s","late"))
        result,xs=self.check_run(lambda *_:[])
        self.assertEqual(result[:2],(None,"abstain"))
        self.assertEqual(xs,self.fixed)
