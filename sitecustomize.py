# sitecustomize.py
import asyncio
try:
    from tornado.platform.asyncio import AnyThreadEventLoopPolicy
except Exception:
    class AnyThreadEventLoopPolicy(asyncio.DefaultEventLoopPolicy):
        def get_event_loop(self):
            try:
                return super().get_event_loop()
            except RuntimeError:
                loop = self.new_event_loop()
                self.set_event_loop(loop)
                return loop
asyncio.set_event_loop_policy(AnyThreadEventLoopPolicy())