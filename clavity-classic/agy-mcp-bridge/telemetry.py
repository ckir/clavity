import aiosqlite
import os
import datetime

async def get_db_path(target_dir: str) -> str:
    agent_dir = os.path.join(target_dir, ".agent")
    os.makedirs(agent_dir, exist_ok=True)
    return os.path.join(agent_dir, "telemetry.db")

async def init_db(target_dir: str):
    db_path = await get_db_path(target_dir)
    async with aiosqlite.connect(db_path) as db:
        await db.execute('''
            CREATE TABLE IF NOT EXISTS invocations (
                task_id TEXT PRIMARY KEY,
                prompt TEXT,
                start_time TEXT,
                end_time TEXT,
                status TEXT,
                tokens_used INTEGER,
                final_error TEXT
            )
        ''')
        await db.commit()

async def log_start(target_dir: str, task_id: str, prompt: str):
    db_path = await get_db_path(target_dir)
    start_time = datetime.datetime.now().isoformat()
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            'INSERT INTO invocations (task_id, prompt, start_time, status) VALUES (?, ?, ?, ?)',
            (task_id, prompt, start_time, "running")
        )
        await db.commit()

async def log_completion(target_dir: str, task_id: str, status: str, tokens_used: int = 0, final_error: str = None):
    db_path = await get_db_path(target_dir)
    end_time = datetime.datetime.now().isoformat()
    async with aiosqlite.connect(db_path) as db:
        await db.execute(
            '''UPDATE invocations 
               SET end_time = ?, status = ?, tokens_used = ?, final_error = ?
               WHERE task_id = ?''',
            (end_time, status, tokens_used, final_error, task_id)
        )
        await db.commit()
