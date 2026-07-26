#include <fcntl.h>
#include <unistd.h>

int mcpx_redirect_stdio_to_devnull(void) {
  int fd = open("/dev/null", O_RDWR);
  if (fd < 0) {
    return -1;
  }

  if (dup2(fd, STDIN_FILENO) < 0 || dup2(fd, STDOUT_FILENO) < 0 ||
      dup2(fd, STDERR_FILENO) < 0) {
    if (fd > STDERR_FILENO) {
      close(fd);
    }
    return -1;
  }

  if (fd > STDERR_FILENO) {
    close(fd);
  }
  return 0;
}
