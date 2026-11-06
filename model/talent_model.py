"""Reference model of the Talent Token rules, used to check the math the contracts implement
and to plan a node sale. Standard library only. Run:  python3 model/talent_model.py
"""
from dataclasses import dataclass, field

MAX_NODES = 5_000


@dataclass
class NodeSale:
    tiers: list  # [(cumulative_cap, price_usd)]
    minted: int = 0

    def __post_init__(self):
        caps = [c for c, _ in self.tiers]
        assert caps == sorted(set(caps)) and caps[-1] == MAX_NODES, "tiers must end exactly at 5,000"

    def quote(self, qty):
        if self.minted + qty > MAX_NODES:
            raise ValueError("sold out")
        cost, cursor, left = 0, self.minted, qty
        for cap, price in self.tiers:
            if cursor >= cap:
                continue
            take = min(cap - cursor, left)
            cost += take * price
            cursor += take
            left -= take
            if not left:
                break
        return cost

    def buy(self, qty):
        c = self.quote(qty)
        self.minted += qty
        return c

    def gross_if_sold_out(self):
        total, prev = 0, 0
        for cap, price in self.tiers:
            total += (cap - prev) * price
            prev = cap
        return total


@dataclass
class Pool:
    raised: float = 0
    released: float = 0
    pending: float = 0
    contributed: dict = field(default_factory=dict)

    def support(self, who, amt):
        self.raised += amt
        self.contributed[who] = self.contributed.get(who, 0) + amt

    def available(self):
        return self.raised - self.released - self.pending

    def refund_of(self, who):
        return self.contributed.get(who, 0) * (self.raised - self.released) / self.raised


def _tests():
    s = NodeSale([(1000, 250), (3000, 500), (5000, 1000)])
    assert s.gross_if_sold_out() == 250_000 + 1_000_000 + 2_000_000
    s.minted = 995
    assert s.quote(8) == 5 * 250 + 3 * 500
    s.minted = 4999
    s.buy(1)
    try:
        s.buy(1)
        raise AssertionError("cap broken")
    except ValueError:
        pass

    p = Pool()
    p.support("a", 600)
    p.support("b", 400)
    p.released = 500
    assert abs(p.refund_of("a") + p.refund_of("b") - 500) < 1e-9
    assert p.refund_of("a") == 300
    print("all model checks passed")


if __name__ == "__main__":
    _tests()
    sale = NodeSale([(1000, 250), (3000, 500), (5000, 1000)])
    print(f"Example tiers -> gross if all 5,000 nodes sell: ${sale.gross_if_sold_out():,.0f}")
