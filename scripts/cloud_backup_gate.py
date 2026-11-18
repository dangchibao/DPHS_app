"""Read opt-in flags after GitHub has attached the private-backup environment."""
import os
from pathlib import Path


def main():
    enabled = all(os.environ.get(name) == 'true' for name in (
        'CLOUD_BACKUP_ENABLED', 'R2_PRIVATE_BACKUP_CONFIRMED'))
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
        output.write(f'enabled={str(enabled).lower()}\n')
    if not enabled:
        with Path(os.environ['GITHUB_STEP_SUMMARY']).open('a', encoding='utf-8') as summary:
            summary.write('### Backup chưa bật\n\n'
                          'Chưa đủ hai cờ xác nhận. Không xuất D1, không gọi R2; '
                          'lượt này không tạo hoặc xác nhận bản sao lưu mới.\n')


if __name__ == '__main__':
    main()
