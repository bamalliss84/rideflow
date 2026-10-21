"use client";

import { AlertTriangle, X } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";

import { useI18n } from "@/components/providers/I18nProvider";

import { Button } from "./Button";
import { Field, Textarea } from "./Form";
import { InlineError } from "./States";

/** Accessible modal built on the native <dialog> (focus trapping, Esc to close, inert background). */
export function Dialog({
  open,
  onClose,
  title,
  description,
  children,
  footer,
  size = "md",
}: {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  size?: "sm" | "md" | "lg" | "xl";
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const { t } = useI18n();
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    if (open && !el.open) el.showModal();
    if (!open && el.open) el.close();
  }, [open]);
  const width = { sm: "max-w-md", md: "max-w-lg", lg: "max-w-2xl", xl: "max-w-4xl" }[size];
  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      className={`m-auto w-[calc(100%-2rem)] ${width} rounded-xl border border-line bg-white p-0 text-ink shadow-pop`}
    >
      {open ? (
        <div className="flex max-h-[85dvh] flex-col">
          <div className="flex items-start justify-between gap-4 border-b border-line px-5 py-4">
            <div>
              <h2 className="text-base font-semibold">{title}</h2>
              {description ? <p className="mt-1 text-sm text-muted">{description}</p> : null}
            </div>
            <button type="button" onClick={onClose} className="-m-1 rounded p-1 text-muted hover:bg-navy-50 hover:text-ink" aria-label={t.common.close}>
              <X className="size-5" aria-hidden />
            </button>
          </div>
          {children ? <div className="overflow-y-auto px-5 py-4">{children}</div> : null}
          {footer ? <div className="flex flex-wrap justify-end gap-2 border-t border-line bg-surface/60 px-5 py-3">{footer}</div> : null}
        </div>
      ) : null}
    </dialog>
  );
}

/**
 * Confirmation for irreversible or sensitive actions. Optional/required note field; the confirm button is
 * disabled while the request runs, preventing double submission.
 */
export interface ConfirmProps {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  message?: ReactNode;
  confirmLabel: string;
  tone?: "primary" | "danger" | "accent";
  note?: { label: string; required?: boolean; placeholder?: string };
  onConfirm: (note: string) => Promise<unknown>;
  extra?: ReactNode;
}

export function ConfirmDialog(props: ConfirmProps) {
  const [busy, setBusy] = useState(false);
  return (
    <Dialog open={props.open} onClose={busy ? () => undefined : props.onClose} title={props.title} size="md">
      {props.open ? <ConfirmBody {...props} busy={busy} setBusy={setBusy} /> : null}
    </Dialog>
  );
}

function ConfirmBody({ onClose, message, confirmLabel, tone = "primary", note, onConfirm, extra, busy, setBusy }: ConfirmProps & {
  busy: boolean;
  setBusy: (v: boolean) => void;
}) {
  const { t } = useI18n();
  const [text, setText] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [touched, setTouched] = useState(false);
  const missing = Boolean(note?.required && !text.trim());

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setTouched(true);
    if (missing || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirm(text.trim());
      setBusy(false);
      onClose();
    } catch (err) {
      setError(err);
      setBusy(false);
    }
  };

  return (
    <form onSubmit={submit} className="space-y-4">
      {message ? (
        <div className="flex gap-3">
          {tone === "danger" ? <AlertTriangle className="mt-0.5 size-5 shrink-0 text-coral-600" aria-hidden /> : null}
          <div className="text-sm leading-relaxed text-ink">{message}</div>
        </div>
      ) : null}
      {extra}
      {note ? (
        <Field label={note.label} required={note.required} error={touched && missing ? t.common.noteRequired : undefined}>
          {(p) => <Textarea {...p} value={text} onChange={(e) => setText(e.target.value)} placeholder={note.placeholder} maxLength={500} />}
        </Field>
      ) : null}
      <p className="text-xs text-muted">{t.common.irreversible}</p>
      <InlineError error={error} />
      <div className="flex flex-wrap justify-end gap-2 pt-1">
        <Button variant="secondary" onClick={onClose} disabled={busy}>
          {t.common.cancel}
        </Button>
        <Button type="submit" variant={tone} loading={busy}>
          {confirmLabel}
        </Button>
      </div>
    </form>
  );
}
