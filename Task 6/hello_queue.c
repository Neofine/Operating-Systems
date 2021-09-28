#include <minix/drivers.h>
#include <minix/chardriver.h>
#include <stdio.h>
#include <stdlib.h>
#include <minix/ds.h>
#include <minix/ioctl.h>
#include <sys/ioc_hello_queue.h>
#include "hello_queue.h"

/*
 * Function prototypes for the hello driver.
 */
static int hello_open(devminor_t minor, int access, endpoint_t user_endpt);
static int hello_close(devminor_t minor);
static ssize_t hello_read(devminor_t minor, u64_t position, endpoint_t endpt,
                          cp_grant_id_t grant, size_t size, int flags, cdev_id_t id);
static ssize_t hello_write(devminor_t minor, u64_t position, endpoint_t endpt,
                           cp_grant_id_t grant, size_t size, int flags, cdev_id_t id);
static ssize_t hello_ioctl(devminor_t minor, unsigned long request, endpoint_t endpt,
                           cp_grant_id_t grant, int flags, endpoint_t user_endpt, cdev_id_t id);

/* SEF functions and variables. */
static void sef_local_startup(void);
static int sef_cb_init(int type, sef_init_info_t *info);
static int save_values(int);
static int restore_values(void);

/* Entry points to the hello driver. */
static struct chardriver hello_tab = {
        .cdr_open	= hello_open,
        .cdr_close	= hello_close,
        .cdr_read	= hello_read,
        .cdr_write = hello_write,
        .cdr_ioctl = hello_ioctl,
};

static size_t queue_length;
static size_t queue_max_size;
static char* queue;

static int hello_open(devminor_t UNUSED(minor), int UNUSED(access),
        endpoint_t UNUSED(user_endpt)) {
  return OK;
}

static int hello_close(devminor_t UNUSED(minor)) {
  return OK;
}

static ssize_t hello_read(devminor_t UNUSED(minor), u64_t position,
                          endpoint_t endpt, cp_grant_id_t grant, size_t size, int UNUSED(flags),
                          cdev_id_t UNUSED(id)) {
  int ret;

  if (queue_length == 0 || size == 0)
    return 0;

  if (size > queue_length)
    size = queue_length;

  if ((ret = sys_safecopyto(endpt, grant, 0, (vir_bytes)queue, size)) != OK)
    return ret;

  for (size_t i = size; i < queue_length; i++)
    queue[i - size] = queue[i];

  queue_length -= size;

  if (queue_max_size > 1 && 4 * queue_length <= queue_max_size) {
    queue_max_size /= 2;
    queue = realloc(queue, queue_max_size * sizeof(char));

    if (queue == NULL)
      exit(1);
  }

  /* Return the number of bytes read. */
  return size;
}

void increase_to(size_t amount) {
  while (amount > queue_max_size)
    queue_max_size *= 2;

  queue = realloc(queue, queue_max_size * sizeof(char));

  if (queue == NULL)
    exit(1);
}

static ssize_t hello_write(devminor_t minor, u64_t pos, endpoint_t ep, cp_grant_id_t gid,
                           size_t size, int UNUSED(flags), cdev_id_t UNUSED(id)) {
  int r;

  if (size == 0)
    return 0;

  increase_to(queue_length + size);

  if ((r = sys_safecopyfrom(ep, gid, 0,
                            (vir_bytes)(queue + (size_t)queue_length), size)) != OK)
    return r;

  queue_length += size;

  return  size;
}

static int hello_ioctl(devminor_t minor, unsigned long request, endpoint_t ep,
                       cp_grant_id_t gid, int UNUSED(flags), endpoint_t UNUSED(user_ep),
                       cdev_id_t UNUSED(id)) {
  /* Process I/O control requests */
  int r;

  if (request == HQIOCRES) {

    queue = realloc(queue, DEVICE_SIZE * sizeof(char));
    if (queue == NULL)
      exit(1);

    queue_length = DEVICE_SIZE;
    queue_max_size = DEVICE_SIZE;
    char letters[] = {'x', 'y', 'z'};
    for (int i = 0 ; i < queue_length; i++)
      queue[i] = letters[i % 3];

    return OK;
  }
  else if (request == HQIOCSET) {
    increase_to(MSG_SIZE);

    int from_where = (int)queue_length - (int)MSG_SIZE;

    if (from_where < 0)
      from_where = 0;

    if ((r = sys_safecopyfrom(ep, gid, 0,
                              (vir_bytes) queue + from_where, MSG_SIZE)) != OK)
      return r;

    queue_length = from_where + MSG_SIZE;

    return r;
  }
  else if (request == HQIOCXCH) {
    char char_input[2];

    if ((r = sys_safecopyfrom(ep, gid, 0,
                               (vir_bytes)(char_input), 2)) != OK)
      return r;

    for (int i = 0; i < queue_length; i++) {
      if (queue[i] == char_input[0]) {
        queue[i]  = char_input[1];
      }
    }

    return OK;
  }
  else if (request == HQIOCDEL) {
    size_t to_del = 0;
    for (int i = 0; i < queue_length; i++) {
      if (i % 3 == 2)
        to_del++;
      else
        queue[i - to_del] = queue[i];
    }
    queue_length -= to_del;

    return OK;
  }

  return ENOTTY;
}

static int save_values(int UNUSED(state)) {

  ds_publish_u32("buffer_len", queue_length, DSF_OVERWRITE);
  ds_publish_u32("buffer_max", queue_max_size, DSF_OVERWRITE);
  ds_publish_mem("buffer", queue, queue_max_size, DSF_OVERWRITE);

  return OK;
}

static int restore_values() {
  ds_retrieve_u32("buffer_len", &queue_length);
  ds_delete_u32("buffer_len");

  ds_retrieve_u32("buffer_max", &queue_max_size);
  ds_delete_u32("buffer_max");

  queue = malloc(queue_max_size * sizeof(char));
  if (queue == NULL)
    exit(1);
  ds_retrieve_mem("buffer", queue, &queue_max_size);
  ds_delete_mem("buffer");

  return OK;
}

static void sef_cb_signal_handler(int signo)
{
  /* Only check for termination signal, ignore anything else. */
  if (signo != SIGTERM) return;

  save_values(0);

  exit(0);
}
static void sef_local_startup() {
  /*
   * Register init callbacks. Use the same function for all event types
   */
  sef_setcb_init_fresh(sef_cb_init);
  sef_setcb_init_lu(sef_cb_init);
  sef_setcb_init_restart(sef_cb_init);

  /*
   * Register live update callbacks.
   */
  /* - Agree to update immediately when LU is requested in a valid state. */
  sef_setcb_lu_prepare(sef_cb_lu_prepare_always_ready);
  /* - Support live update starting from any standard state. */
  sef_setcb_lu_state_isvalid(sef_cb_lu_state_isvalid_standard);
  /* - Register a custom routine to save the state. */
  sef_setcb_lu_state_save(save_values);

  sef_setcb_signal_handler(sef_cb_signal_handler);

  /* Let SEF perform startup. */
  sef_startup();
}

static int sef_cb_init(int type, sef_init_info_t *UNUSED(info))
{
  /* Initialize the hello driver. */
  int do_announce_driver = TRUE;

  switch(type) {
    case SEF_INIT_FRESH:

      queue = malloc(DEVICE_SIZE * sizeof(char));
      if (queue == NULL)
        exit(1);
      queue_length = DEVICE_SIZE;
      queue_max_size = DEVICE_SIZE;
      char letters[] = {'x', 'y', 'z'};
      for (int i = 0 ; i < queue_length; i++)
        queue[i] = letters[i % 3];

      break;

    case SEF_INIT_LU:
      restore_values();
      do_announce_driver = FALSE;

      break;

    case SEF_INIT_RESTART:
      restore_values();
      break;
  }

  /* Announce we are up when necessary. */
  if (do_announce_driver) {
    chardriver_announce();
  }

  /* Initialization completed successfully. */
  return OK;
}

int main(void)
{
  /*
   * Perform initialization.
   */
  sef_local_startup();

  /*
   * Run the main loop.
   */
  chardriver_task(&hello_tab);

  free(queue);
  return OK;
}