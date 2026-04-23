#define _GNU_SOURCE

#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

static int path_exists(const char *path)
{
	struct stat st;

	return stat(path, &st) == 0;
}

static int move_mount_into_root(const char *old_path, const char *new_root,
				 const char *suffix)
{
	char new_path[PATH_MAX];

	if (!path_exists(old_path))
		return 0;

	if (snprintf(new_path, sizeof(new_path), "%s/%s", new_root, suffix) >=
	    (int)sizeof(new_path))
		return -1;

	if (!path_exists(new_path))
		return 0;

	if (mount(old_path, new_path, NULL, MS_MOVE, NULL) == 0)
		return 0;

	if (errno == EINVAL || errno == ENOENT)
		return 0;

	return -1;
}

int main(int argc, char **argv)
{
	char **new_argv;
	const char *new_root;
	const char *init_path;

	if (argc < 3)
		return 2;

	new_root = argv[1];
	init_path = argv[2];

	if (move_mount_into_root("/dev", new_root, "dev") < 0)
		return 3;
	if (move_mount_into_root("/proc", new_root, "proc") < 0)
		return 4;
	if (move_mount_into_root("/sys", new_root, "sys") < 0)
		return 5;
	if (move_mount_into_root("/run", new_root, "run") < 0)
		return 6;

	if (chdir(new_root) < 0)
		return 7;
	if (chroot(".") < 0)
		return 8;
	if (chdir("/") < 0)
		return 9;

	new_argv = &argv[2];
	execv(init_path, new_argv);
	return 10;
}